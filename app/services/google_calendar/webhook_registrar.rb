# frozen_string_literal: true

module GoogleCalendar
  # Registers the Google Calendar push channel (config/recurring.yml, every Sunday). Each call creates one new
  # channel, hands the calendar's sync token to it, and then retires every other channel: Google is told to stop
  # it (an expired or unknown one is simply forgotten) and its row is removed, so one channel is live at a time
  # and the rows do not pile up.
  #
  # Runs are serialised by a transaction-level advisory lock, and a run retires only the channels created before
  # its own, so overlapping runs (a host cron line and Solid Queue during a deploy, the renew job) leave exactly
  # one live channel: the newest.
  class WebhookRegistrar
    LOCK_KEY = Zlib.crc32("google_calendar_webhook_registrar")

    def self.register!
      GoogleCalendarChannel.transaction do
        GoogleCalendarChannel.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
        register_locked!
      end
    end

    def self.register_locked!
      service = Google::Apis::CalendarV3::CalendarService.new
      service.authorization = SubSpaceBooking.authorizer

      channel = Google::Apis::CalendarV3::Channel.new(
        id: SecureRandom.uuid,
        type: "web_hook",
        address: webhook_url
      )

      response = service.watch_event("primary", channel)

      # A sync token belongs to the calendar listing, not to a channel: keep the newest one.
      sync_token = GoogleCalendarChannel.where.not(sync_token: nil).order(expires_at: :desc).pick(:sync_token)

      created = GoogleCalendarChannel.create!(
        channel_id: response.id,
        resource_id: response.resource_id,
        expires_at: Time.at(response.expiration.to_i / 1000),
        sync_token: sync_token
      )

      retire_other_channels(service, except: created)
      created
    end
    private_class_method :register_locked!

    def self.retire_other_channels(service, except:)
      GoogleCalendarChannel.where(id: ...except.id).find_each do |old|
        stop(service, old) if old.expires_at > Time.current
        old.destroy!
      rescue Google::Apis::ClientError
        old.destroy! # Google no longer knows the channel
      rescue Google::Apis::Error, Signet::AuthorizationError => e
        # Keep the row: the next registration tries to stop it again.
        Rails.error.report(e, handled: true, context: { service: name, channel_id: old.channel_id })
      end
    end
    private_class_method :retire_other_channels

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
