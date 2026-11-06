# frozen_string_literal: true

module GoogleCalendar
  # Moves an Event's Google event from the calendar it was in to the calendar of the event's space as it is now,
  # keeping its id, then pushes the event's current state. Queued when an update changes the space.
  class EventMoveJob < EventPushJob
    def perform(event_id, from_calendar_id)
      event = publishable_event(event_id)
      EventPublisher.new.move_and_push(event, from_calendar_id) if event
    end
  end
end
