# frozen_string_literal: true

module GoogleCalendar
  # Creates the Google Calendar event of one shadowing shift. The shift carries the id its event is created with, so
  # a repeat of this job never makes a second event: Google answers an id that already exists with 409, which means
  # the event is there. Nothing happens when the shift is gone. Once Google has the event (or there is nothing to
  # send), the pending change recorded for it is settled; a failure leaves it for GoogleCalendar::ResendJob.
  class ShadowingPushJob < EventJob
    # Shadowing hour ids are not event ids: their own concurrency group keeps the two apart.
    limits_concurrency to: 1, key: ->(shadowing_hour_id) { shadowing_hour_id }, group: "GoogleCalendarShadowingHour", duration: 5.minutes

    def perform(shadowing_hour_id)
      started_at = Time.current
      shift = ShadowingHour.find_by(id: shadowing_hour_id)
      shift&.publish_to_calendar
      PendingChange.settle_shadow_push(shadowing_hour_id, started_at)
    end

    private

    def failure_context
      { shadowing_hour_id: arguments.first }
    end
  end
end
