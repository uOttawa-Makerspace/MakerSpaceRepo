# frozen_string_literal: true

module GoogleCalendar
  # Builds the Google Calendar event sent for an Event: title, description, times, time zone, attendees and the
  # recurrence lines.
  class EventPayload
    TIME_ZONE = "America/Toronto"
    LANGUAGES = { "en" => "English", "fr" => "French" }.freeze

    def initialize(event)
      @event = event
    end

    def build
      gcal_event = Google::Apis::CalendarV3::Event.new(
        summary: @event.display_title(include_draft_indicator: false),
        description: description,
        start: event_time(@event.start_time),
        end: event_time(@event.end_time),
        attendees: attendees
      )
      lines = recurrence_lines
      gcal_event.recurrence = lines if lines.any?
      gcal_event
    end

    private

    def event_time(time)
      Google::Apis::CalendarV3::EventDateTime.new(date_time: time.iso8601, time_zone: TIME_ZONE)
    end

    def attendees
      return [] if Rails.env.test?

      @event.users.map { |user| Google::Apis::CalendarV3::EventAttendee.new(email: user.email) }
    end

    def description
      text = @event.description.to_s
      return text unless @event.event_type == "training" && @event.training_id.present?

      [text, training_details].reject(&:blank?).join("\n\n")
    end

    def training_details
      language = LANGUAGES.fetch(@event.language) { @event.language.to_s }
      [
        "Training: #{@event.training&.name_en || @event.training&.name}",
        "Language: #{language}",
        ("Course: #{@event.course_name.name}" if @event.course_name.present?)
      ].compact.join("\n")
    end

    def recurrence_lines
      return [] if @event.recurrence_rule.blank?

      @event.recurrence_rule.strip.lines.map(&:strip).select do |line|
        line.start_with?("RRULE:", "EXDATE:")
      end
    end
  end
end
