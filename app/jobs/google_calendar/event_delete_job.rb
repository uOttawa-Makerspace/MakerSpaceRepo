# frozen_string_literal: true

module GoogleCalendar
  # Removes a Google Calendar event after its Event was destroyed. It takes the Google event id and the calendar
  # id, captured before the destroy, because the row is gone by the time the job runs. The event id is only the
  # key that keeps it from running at the same time as a push of the same event.
  class EventDeleteJob < EventJob
    def perform(google_event_id, calendar_id, _event_id)
      EventPublisher.new.remove(google_event_id, calendar_id)
    end

    private

    def failure_context
      { google_event_id: arguments.first }
    end
  end
end
