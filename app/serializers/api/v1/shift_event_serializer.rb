# frozen_string_literal: true

require "ice_cube"

module Api
  module V1
    # Published shift events of a space inside a window, shaped for FullCalendar:
    # [{id, title, start, end, allDay, extendedProps{eventType, description, background}}].
    # Same rules as the legacy staff/my_calendar#json: a one-off event must lie
    # fully inside the window; a recurring event is expanded to its occurrences
    # that start in the window. Unlike the legacy, assignees and their colours
    # are preloaded (no per-event queries), and only the fields the app reads are
    # sent (no name/draft/hasCurrentUser). Assignee names appear in `title`, as
    # in the legacy; no email or other user column is sent.
    module ShiftEventSerializer
      DEFAULT_COLOR = "#3788d8"

      module_function

      def call(space:, from:, to:, user_id: nil)
        events = Event.where(space_id: space.id, draft: false, event_type: "shift")
                      .where("((events.recurrence_rule IS NULL OR events.recurrence_rule = '') AND events.start_time >= :from AND events.end_time <= :to) " \
                             "OR (events.recurrence_rule <> '' AND events.start_time < :to)", from: from, to: to)
        events = events.where(id: EventAssignment.where(user_id: user_id).select(:event_id)) if user_id
        events = events.includes(event_assignments: :user).order(:start_time, :id)
        colors = StaffSpace.where(space_id: space.id).pluck(:user_id, :color).to_h

        events.flat_map do |event|
          if event.recurrence_rule.present?
            expand(event, from, to, colors)
          else
            [format(event, colors)]
          end
        end
      end

      def expand(event, from, to, colors)
        rule_line = event.recurrence_rule.lines.find { |l| l.start_with?("RRULE:") } ||
                    (event.recurrence_rule.include?("RRULE:") ? event.recurrence_rule : "RRULE:#{event.recurrence_rule}")
        schedule = IceCube::Schedule.new(event.start_time)
        schedule.add_recurrence_rule(IceCube::Rule.from_ical(rule_line.gsub("RRULE:", "").strip))
        duration = event.end_time - event.start_time
        schedule.occurrences_between(from, to).map do |occ|
          format(event, colors, occ, occ + duration).merge(id: "event-#{event.id}-#{occ.to_i}")
        end
      rescue StandardError
        # A rule IceCube cannot parse: show the event once if it is inside the window (legacy behaviour).
        event.start_time >= from && event.end_time <= to ? [format(event, colors)] : []
      end

      def format(event, colors, start_time = event.start_time, end_time = event.end_time)
        assignments = event.event_assignments.select(&:user)
        {
          id: "event-#{event.id}",
          title: event.display_title,
          start: start_time.iso8601,
          end: end_time.iso8601,
          allDay: start_time.to_time == end_time.to_time - 1.day,
          extendedProps: {
            eventType: event.event_type,
            description: event.description,
            background: background(assignments, colors)
          }
        }
      end

      def background(assignments, colors)
        return DEFAULT_COLOR if assignments.empty?

        n = assignments.size
        stops = assignments.each_with_index.map do |ea, i|
          c = colors[ea.user_id].presence || DEFAULT_COLOR
          "#{c} #{(100.0 / n) * i}%, #{c} #{(100.0 / n) * (i + 1)}%"
        end
        "linear-gradient(to right, #{stops.join(', ')});"
      end
    end
  end
end
