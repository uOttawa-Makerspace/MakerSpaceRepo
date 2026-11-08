# frozen_string_literal: true

# Mirrors the primary Google Calendar into SubSpaceBookings (see GoogleCalendar::EventProcessor). Runs when Google
# pushes a change (GoogleCalendarController#webhook) and, on staging, every Sunday as a catch-up
# (config/recurring.yml).
#
# Lists every page. The sync token of the active channel makes the listing incremental; when Google refuses it
# (410: expired) the token is dropped and the calendar is listed in full, once. Any other client error, or a
# second one, is raised. One event that cannot be processed (bad data) is reported and skipped; it does not stop
# the others, and the new sync token is still stored. A transient database error is not that: it fails the job.
class GoogleCalendarSyncJob < ApplicationJob
  queue_as :default

  # Google sends several pushes per change. One sync at a time: a second waits for the first (and then lists
  # from the token the first stored) instead of racing it over the same events and the same sync token.
  limits_concurrency to: 1, key: -> { "google_calendar_sync" }, duration: 15.minutes

  # A failure of the database or its connection says nothing about the event, so it fails the job (the token
  # does not advance past an event that was never processed) instead of being reported and skipped.
  TRANSIENT_DATABASE_ERRORS = [
    ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::SerializationFailure,
    ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed, ActiveRecord::ConnectionTimeoutError
  ].freeze

  def perform
    logger.info "[GCAL] Sync job triggered"

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = SubSpaceBooking.authorizer

    # Use the most recent active channel to get the sync token
    channel = GoogleCalendarChannel.active.order(expires_at: :desc).first
    next_sync_token = list_and_process(service, channel&.sync_token) do
      channel&.update!(sync_token: nil)
    end

    # Save the next sync token in the channel
    channel.update!(sync_token: next_sync_token) if channel && next_sync_token
  end

  private

  # Returns the sync token of the listing's last page. The block runs when Google rejects +sync_token+.
  def list_and_process(service, sync_token)
    list_pages(service, sync_token) { |event| process(event) }
  rescue Google::Apis::ClientError => e
    raise unless e.status_code == 410 && sync_token.present?

    logger.warn "[GCAL] Sync token rejected (410); listing the whole calendar"
    yield
    list_pages(service, nil) { |event| process(event) }
  end

  def list_pages(service, sync_token)
    page_token = nil
    total = 0
    loop do
      options = { show_deleted: true, single_events: true }
      options[:sync_token] = sync_token if sync_token.present?
      options[:page_token] = page_token if page_token.present?
      response = service.list_events("primary", **options)

      response.items.to_a.each do |event|
        total += 1
        yield event
      end

      page_token = response.next_page_token
      unless page_token.present?
        logger.warn "[GCAL] Number of events fetched: #{total}"
        return response.next_sync_token
      end
    end
  end

  def process(event)
    GoogleCalendar::EventProcessor.process(event)
  rescue *TRANSIENT_DATABASE_ERRORS
    raise
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { job: self.class.name, google_event_id: event.id })
  end
end
