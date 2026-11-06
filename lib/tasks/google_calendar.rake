# frozen_string_literal: true

namespace :google_calendar do
  desc "List Google Calendar events that look like duplicates of stored events, or that belong to an event of another calendar (read-only; changes nothing)"
  task duplicate_events: :environment do
    rows = GoogleCalendar::DuplicateEventReport.new(GoogleCalendar::EventPublisher.service).rows
    rows.each { |row| puts [row.calendar_id, row.google_event_id, row.summary, row.start&.iso8601, row.reason].join("\t") }
    puts "#{rows.size} possible duplicate(s)"
  end
end
