# frozen_string_literal: true

module GoogleCalendar
  # Read-only. Finds events in a space's Google Calendar that no stored Event should have there:
  # - a copy: same title and start as a stored Event of that calendar, but an id no stored Event owns;
  # - a leftover: an id that belongs to a stored Event of another calendar (the event was moved and the removal
  #   from the old calendar did not happen).
  # Nothing is changed in Google or in the database.
  class DuplicateEventReport
    Row = Struct.new(:calendar_id, :google_event_id, :summary, :start, :reason, keyword_init: true)

    def initialize(service)
      @service = service
    end

    def rows
      calendar_ids.flat_map do |calendar_id|
        keys = events_by_calendar.fetch(calendar_id, []).to_set { |event| key(event.display_title(include_draft_indicator: false), event.start_time) }
        google_events(calendar_id).filter_map do |item|
          reason = reason_for(item, calendar_id, keys)
          next unless reason

          Row.new(calendar_id: calendar_id, google_event_id: item.id, summary: item.summary,
                  start: item_start(item), reason: reason)
        end
      end
    end

    private

    # :leftover, :copy, or nil when the item is fine.
    def reason_for(item, calendar_id, keys)
      owner = owner_calendars[item.id]
      return nil if owner == calendar_id
      return :leftover if owner

      :copy if keys.include?(key(item.summary, item_start(item)))
    end

    def owner_calendars
      @owner_calendars ||= events_by_calendar.each_with_object({}) do |(calendar_id, events), owners|
        events.each { |event| owners[event.google_event_id] = calendar_id if event.google_event_id.present? }
      end
    end

    # Every calendar of a space, also one with no stored event (a leftover can sit in it).
    def calendar_ids
      Space.all.map { |space| EventPublisher.calendar_id_for(space) }.uniq
    end

    def events_by_calendar
      @events_by_calendar ||= Event.includes(:space).group_by do |event|
        EventPublisher.calendar_id_for(event.space)
      end
    end

    def google_events(calendar_id)
      items = []
      page_token = nil
      loop do
        page = @service.list_events(calendar_id, max_results: 2500, page_token: page_token)
        items.concat(Array(page.items))
        page_token = page.next_page_token
        break if page_token.blank?
      end
      items
    end

    def item_start(item)
      time = item.start&.date_time
      time&.to_time&.utc
    end

    def key(summary, start)
      [summary.to_s, start&.to_i]
    end
  end
end
