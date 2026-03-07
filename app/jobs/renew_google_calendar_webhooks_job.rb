class RenewGoogleCalendarWebhooksJob < ApplicationJob
  queue_as :default

  def perform
    GoogleCalendarChannel.expiring_soon.find_each do |channel|
      GoogleCalendar::WebhookRegistrar.register!
      channel.destroy
    end
  end
end