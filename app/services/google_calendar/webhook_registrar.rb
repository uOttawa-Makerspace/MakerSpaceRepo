module GoogleCalendar
  class WebhookRegistrar
    def self.register!
      service = Google::Apis::CalendarV3::CalendarService.new
      service.authorization = SubSpaceBooking.authorizer

      channel = Google::Apis::CalendarV3::Channel.new(
        id: SecureRandom.uuid,
        type: "web_hook",
        address: webhook_url
      )

      response = service.watch_event("primary", channel)

      GoogleCalendarChannel.create!(
        channel_id: response.id,
        resource_id: response.resource_id,
        expires_at: Time.at(response.expiration.to_i / 1000)
      )
    end

    def self.webhook_url
      if Rails.env.production?
        "https://makerepo.com/google/calendar/webhook"
      else
        "https://staging.makerepo.com/google/calendar/webhook"
      end
    end
  end
end