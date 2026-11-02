# frozen_string_literal: true

# Chunk 18 helpers (reporting + integrations characterization). Opt-in: include
# `Chunk18Helpers` inside the describe blocks that need it. Method names carry a
# `c18_` prefix because `log_in!`, `sign_in_as` and `deliveries` are global.
require "roo"
require "tempfile"

module Chunk18Helpers
  C18_ROLE_TRAITS = { regular: :regular_user, staff: :staff, admin: :admin }.freeze

  # Real login through the app; returns the user (nil for :guest).
  def c18_sign_in(role)
    return nil if role == :guest

    user = create(:user, C18_ROLE_TRAITS.fetch(role))
    post login_authentication_path,
         params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
    user
  end

  # Parses an XLSX byte string with roo and returns { sheet_name => [[cells]] }.
  # Fully empty cells are nil; dates come back as Date/DateTime values.
  def c18_xlsx_sheets(bytes)
    file = Tempfile.new(["c18", ".xlsx"])
    file.binmode
    file.write(bytes)
    file.flush
    xlsx = Roo::Excelx.new(file.path)
    xlsx.sheets.to_h { |name| [name, xlsx.sheet(name).to_a] }
  ensure
    file&.close!
  end
end

# Builders for Google Calendar API objects (google-apis-calendar_v3), used by
# the EventProcessor / GoogleCalendarSyncJob / WebhookRegistrar specs.
module Chunk18GoogleHelpers
  GC = Google::Apis::CalendarV3

  def c18_gcal_event(id: "evt-1", summary: "Team meeting", description: "Weekly", location: "STM 124",
                     status: "confirmed", start_at: Time.utc(2027, 4, 5, 14), end_at: Time.utc(2027, 4, 5, 15),
                     creator_email: "creator@example.test", start_nil: false, end_nil: false)
    GC::Event.new(
      id: id, summary: summary, description: description, location: location, status: status,
      start: start_nil ? nil : GC::EventDateTime.new(date_time: start_at.to_datetime),
      end: end_nil ? nil : GC::EventDateTime.new(date_time: end_at.to_datetime),
      creator: creator_email && GC::Event::Creator.new(email: creator_email)
    )
  end

  # JSON for a calendar events.list response (what WebMock returns).
  def c18_gcal_events_json(events, next_sync_token: nil, next_page_token: nil)
    items = events.map do |e|
      h = { "id" => e.id, "summary" => e.summary, "description" => e.description, "location" => e.location,
            "status" => e.status }
      h["start"] = { "dateTime" => e.start.date_time.iso8601 } if e.start
      h["end"] = { "dateTime" => e.end.date_time.iso8601 } if e.end
      h["creator"] = { "email" => e.creator.email } if e.creator
      h
    end
    { "kind" => "calendar#events", "items" => items, "nextSyncToken" => next_sync_token,
      "nextPageToken" => next_page_token }.compact.to_json
  end
end
