# frozen_string_literal: true

# Registers a fresh channel when one is about to expire. The weekly GoogleCalendar::WebhookRegistrar.register!
# in config/recurring.yml is what keeps the channel alive; this is the on-demand form of the same step.
class RenewGoogleCalendarWebhooksJob < ApplicationJob
  queue_as :default

  def perform
    GoogleCalendar::WebhookRegistrar.register! if GoogleCalendarChannel.expiring_soon.exists?
  end
end
