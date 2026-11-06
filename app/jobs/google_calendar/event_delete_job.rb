# frozen_string_literal: true

module GoogleCalendar
  # Removes a Google Calendar event after its Event was destroyed. It takes the Google event id and the calendar
  # id, captured before the destroy, because the row is gone by the time the job runs.
  class EventDeleteJob < EventJob
    # +event_id+ is given when the event still exists (it was moved to another calendar). If it has since come back
    # to this calendar under the same Google id, the copy is live again and must stay.
    def perform(google_event_id, calendar_id, event_id = nil)
      return if live_in_calendar?(event_id, google_event_id, calendar_id)

      EventPublisher.new.remove(google_event_id, calendar_id)
    end

    private

    def live_in_calendar?(event_id, google_event_id, calendar_id)
      event = Event.find_by(id: event_id) if event_id
      event.present? && event.google_event_id == google_event_id &&
        EventPublisher.calendar_id_for(event.space) == calendar_id
    end

    def failure_context
      { google_event_id: arguments.first }
    end
  end
end
