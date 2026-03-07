class GoogleCalendarSyncJob < ApplicationJob
  queue_as :default

  def perform
    logger.info "[GCAL] Sync job triggered"

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = SubSpaceBooking.authorizer

    # Use the most recent active channel to get the sync token
    channel = GoogleCalendarChannel.active.order(expires_at: :desc).first
    sync_token = channel&.sync_token

    response =
      if sync_token.present?
        service.list_events(
          "primary", # calendar
          sync_token: sync_token,
          show_deleted: true,
          single_events: true
        )
      else
        service.list_events(
          "primary", # calendar
          show_deleted: true,
          single_events: true
        )
      end

    logger.warn "[GCAL] Number of events fetched: #{response.items.size}"

    response.items.each do |event|
      GoogleCalendar::EventProcessor.process(event)
    end

    # Save the next sync token in the channel
    channel.update!(sync_token: response.next_sync_token) if channel && response.next_sync_token
  rescue Google::Apis::ClientError => e
    channel&.update!(sync_token: nil)
    retry
  end
end
