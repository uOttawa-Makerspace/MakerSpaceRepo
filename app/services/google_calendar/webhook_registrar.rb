# frozen_string_literal: true

module GoogleCalendar
  # Registers the Google Calendar push channel (config/recurring.yml, every Sunday). Each call creates one new
  # channel, hands the calendar's sync token to it, and then retires every other channel: Google is told to stop
  # it (an expired or unknown one is simply forgotten) and its row is removed, so one channel is live at a time
  # and the rows do not pile up.
  #
  # Runs are serialised by a session-level advisory lock (no outer transaction, so each step commits on its own),
  # and a run retires only the channels created before its own, so overlapping runs (a host cron line and Solid
  # Queue during a deploy, the renew job) leave exactly one live channel: the newest.
  #
  # Step A creates the new channel at Google and commits its row; if the row cannot be saved, the channel is stopped
  # again and the old ones are left alone. Step B retires the older channels one at a time, after A has committed;
  # a failure on one is reported and the others carry on, so the new channel always survives (a leftover old channel
  # only means duplicate pushes, which the sync handles).
  class WebhookRegistrar
    LOCK_KEY = Zlib.crc32("google_calendar_webhook_registrar")
    LOCK_WAIT = "60s"

    def self.register!
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        with_lock(connection) do
          service = Google::Apis::CalendarV3::CalendarService.new
          service.authorization = SubSpaceBooking.authorizer
          created = create_channel(service)
          retire_older_channels(service, before: created)
          created
        end
      end
    end

    def self.with_lock(connection)
      locked = false
      begin
        connection.execute("SET lock_timeout = '#{LOCK_WAIT}'")
        connection.execute("SELECT pg_advisory_lock(#{LOCK_KEY})")
        locked = true
      ensure
        connection.execute("RESET lock_timeout")
      end
      yield
    ensure
      connection.execute("SELECT pg_advisory_unlock(#{LOCK_KEY})") if locked
    end
    private_class_method :with_lock

    # Step A.
    def self.create_channel(service)
      id = SecureRandom.uuid
      channel = Google::Apis::CalendarV3::Channel.new(
        id: id,
        type: "web_hook",
        address: webhook_url,
        token: GoogleCalendarChannel.token_for(id)
      )

      response = service.watch_event("primary", channel)

      begin
        # A sync token belongs to the calendar listing, not to a channel: keep the newest one.
        sync_token = GoogleCalendarChannel.where.not(sync_token: nil).order(expires_at: :desc).pick(:sync_token)

        GoogleCalendarChannel.create!(
          channel_id: response.id,
          resource_id: response.resource_id,
          expires_at: Time.at(response.expiration.to_i / 1000),
          sync_token: sync_token
        )
      rescue StandardError
        # No row, so nothing would ever stop it: stop it now. The old channels are untouched.
        begin
          service.stop_channel(Google::Apis::CalendarV3::Channel.new(id: response.id, resource_id: response.resource_id))
        rescue StandardError => stop_error
          Rails.error.report(stop_error, handled: true, context: { service: name, channel_id: response.id })
        end
        raise
      end
    end
    private_class_method :create_channel

    # Step B.
    def self.retire_older_channels(service, before:)
      GoogleCalendarChannel.where(id: ...before.id).find_each do |old|
        retire(service, old)
      rescue StandardError => e
        # Keep the row (if it is still there): the next registration tries again.
        Rails.error.report(e, handled: true, context: { service: name, channel_id: old.channel_id })
      end
    end
    private_class_method :retire_older_channels

    def self.retire(service, old)
      begin
        stop(service, old) if old.expires_at > Time.current
      rescue Google::Apis::ClientError
        nil # Google no longer knows the channel
      end
      old.destroy!
    end
    private_class_method :retire

    def self.stop(service, old)
      service.stop_channel(
        Google::Apis::CalendarV3::Channel.new(id: old.channel_id, resource_id: old.resource_id)
      )
    end
    private_class_method :stop

    def self.webhook_url
      if Rails.env.production?
        "https://makerepo.com/google/calendar/webhook"
      else
        "https://staging.makerepo.com/google/calendar/webhook"
      end
    end
  end
end
