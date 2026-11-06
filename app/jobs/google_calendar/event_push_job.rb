# frozen_string_literal: true

module GoogleCalendar
  # Pushes the current state of one Event to Google Calendar. The event is read when the job runs, so the latest
  # state wins however many pushes were queued. Nothing happens when the event is gone or is a draft (drafts are
  # never pushed).
  class EventPushJob < EventJob
    def perform(event_id)
      event = publishable_event(event_id)
      EventPublisher.new.push(event) if event
    end

    private

    def publishable_event(event_id)
      event = Event.find_by(id: event_id)
      event unless event.nil? || event.draft
    end

    def failure_context
      { event_id: arguments.first }
    end
  end
end
