# frozen_string_literal: true

module GoogleCalendar
  # Read-only. Finds events in a space's Google Calendar that look like a second copy of a stored Event: same
  # title and start, but an id that no stored Event owns. Nothing is changed in Google or in the database.
  class DuplicateEventReport
    Row = Struct.new(:calendar_id, :google_event_id, :summary, :start, keyword_init: true)

    def initialize(service)
      @service = service
    end

    def rows
      events_by_calendar.flat_map do |calendar_id, events|
        known_ids = events.filter_map(&:google_event_id).to_set
        keys = events.to_set { |event| key(event.display_title(include_draft_indicator: false), event.start_time) }
        google_events(calendar_id).filter_map do |item|
          next if known_ids.include?(item.id) || !keys.include?(key(item.summary, item_start(item)))

          Row.new(calendar_id: calendar_id, google_event_id: item.id, summary: item.summary, start: item_start(item))
        end
      end
    end

    private

    def events_by_calendar
      Event.includes(:space).group_by do |event|
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
