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
      # A recurrence rule is admin-entered and unvalidated (FREQ=MINUTELY gives
      # 144k occurrences in 100 days), so the work is bounded: occurrences are
      # enumerated lazily and enumeration stops at these caps.
      MAX_OCCURRENCES_PER_EVENT = 500
      MAX_ITEMS = 2000

      Result = Struct.new(:items, :truncated)

      module_function

      def call(**)
        result(**).items
      end

      # Same as `call`, but also says whether a cap cut the response short.
      def result(space:, from:, to:, user_id: nil)
        events = Event.where(space_id: space.id, draft: false, event_type: "shift")
                      .where("((events.recurrence_rule IS NULL OR events.recurrence_rule = '') AND events.start_time >= :from AND events.end_time <= :to) " \
                             "OR (events.recurrence_rule <> '' AND events.start_time < :to)", from: from, to: to)
        events = events.where(id: EventAssignment.where(user_id: user_id).select(:event_id)) if user_id
        events = events.includes(event_assignments: :user).order(:start_time, :id)
        colors = StaffSpace.where(space_id: space.id).pluck(:user_id, :color).to_h

        items = []
        truncated = false
        events.each do |event|
          if items.size >= MAX_ITEMS
            truncated = true
            break
          end
          if event.recurrence_rule.present?
            room = MAX_ITEMS - items.size
            found = expand(event, from, to, colors, [room, MAX_OCCURRENCES_PER_EVENT].min)
            truncated ||= found.truncated
            items.concat(found.items)
          else
            items << format(event, colors)
          end
        end
        Result.new(items, truncated)
      end

      def expand(event, from, to, colors, limit = MAX_OCCURRENCES_PER_EVENT)
        rule_line = event.recurrence_rule.lines.find { |l| l.start_with?("RRULE:") } ||
                    (event.recurrence_rule.include?("RRULE:") ? event.recurrence_rule : "RRULE:#{event.recurrence_rule}")
        schedule = IceCube::Schedule.new(event.start_time)
        schedule.add_recurrence_rule(IceCube::Rule.from_ical(rule_line.gsub("RRULE:", "").strip))
        duration = event.end_time - event.start_time
        # Lazy: stops after limit + 1 occurrences (the extra one only detects truncation).
        # (enumerate_occurrences is private in IceCube but is the only variant taking a closing time.)
        occs = schedule.send(:enumerate_occurrences, from, to).lazy.first(limit + 1)
        items = occs.first(limit).map do |occ|
          format(event, colors, occ, occ + duration).merge(id: "event-#{event.id}-#{occ.to_i}")
        end
        Result.new(items, occs.size > limit)
      rescue StandardError
        # A rule IceCube cannot parse: show the event once if it is inside the window (legacy behaviour).
        Result.new(event.start_time >= from && event.end_time <= to ? [format(event, colors)] : [], false)
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
