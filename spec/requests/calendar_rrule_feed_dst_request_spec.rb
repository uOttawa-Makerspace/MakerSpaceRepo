# frozen_string_literal: true

require "rails_helper"

# The repeat rule strings the admin events feed, the admin unavailabilities
# feed and the staff unavailabilities feed send to the browser, for weekly
# series across the America/Toronto clock changes of 2027 (forward Sunday
# 2027-03-14 at 02:00, back Sunday 2027-11-07 at 02:00). The browser expands
# them with @fullcalendar/rrule in the Toronto zone; the same strings are drawn
# in spec/javascript/calendars/rrule_feed_dst.test.js. Each example also lists
# what the server's own expansion (RecurrenceExpansion, used by the staff
# calendar and the shifts API) gives for the same series, so the two can be
# compared.
RSpec.describe "Repeat rules sent by the calendar feeds across clock changes", type: :request do
  include SpacesSpecHelpers

  let(:zone) { ActiveSupport::TimeZone["America/Toronto"] }
  let!(:space) { create(:space) }

  def stamp(time) = time.utc.strftime("%Y%m%dT%H%M%SZ")

  def server_occurrences(rule, start)
    RecurrenceExpansion.occurrences(rule, start, start, start + 27.days, 10).occurrences.map { |time| time.iso8601 }
  end

  # Each scenario: the first occurrence, the rule as stored, the rule the feeds send and the occurrences the
  # server's expansion gives over four weeks.
  scenarios = {
    "a series at 01:30 over the clocks going back" => {
      start: [2027, 10, 31, 1, 30],
      stored: "DTSTART:%<start>s\nRRULE:FREQ=WEEKLY;BYDAY=SU",
      sent: "DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU",
      server: %w[2027-10-31T01:30:00-04:00 2027-11-07T01:30:00-04:00 2027-11-14T01:30:00-05:00 2027-11-21T01:30:00-05:00]
    },
    "the same series without the occurrence at the first 01:30 of the change day" => {
      start: [2027, 10, 31, 1, 30],
      stored: "DTSTART:%<start>s\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20271107T053000Z",
      sent: "DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20271107T013000",
      server: %w[2027-10-31T01:30:00-04:00 2027-11-14T01:30:00-05:00 2027-11-21T01:30:00-05:00]
    },
    "a series at 10:00 over the clocks going forward" => {
      start: [2027, 3, 7, 10, 0],
      stored: "DTSTART:%<start>s\nRRULE:FREQ=WEEKLY;BYDAY=SU",
      sent: "DTSTART:20270307T100000\nRRULE:FREQ=WEEKLY;BYDAY=SU",
      server: %w[2027-03-07T10:00:00-05:00 2027-03-14T10:00:00-04:00 2027-03-21T10:00:00-04:00 2027-03-28T10:00:00-04:00]
    },
    "a series at 02:30, an hour the clocks skip on the change day" => {
      start: [2027, 3, 7, 2, 30],
      stored: "DTSTART:%<start>s\nRRULE:FREQ=WEEKLY;BYDAY=SU",
      sent: "DTSTART:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU",
      server: %w[2027-03-07T02:30:00-05:00 2027-03-14T03:30:00-04:00 2027-03-21T02:30:00-04:00 2027-03-28T02:30:00-04:00]
    }
  }

  scenarios.each do |name, scenario|
    context "for #{name}" do
      let(:start) { zone.local(*scenario[:start]) }
      let(:stored) { format(scenario[:stored], start: stamp(start)) }

      it "is sent as Toronto wall-clock text by the admin events feed" do
        sign_in_as(:admin)
        event = create(:event, space: space, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
        get json_admin_events_path(id: space.id)
        row = response.parsed_body.flat_map { |group| group["events"] }.find { |r| r["id"] == "event-#{event.id}" }
        expect(row["rrule"]).to eq(scenario[:sent])
        expect(row["duration"]).to eq(3_600_000)
      end

      it "is sent as Toronto wall-clock text by the admin unavailabilities feed" do
        sign_in_as(:admin)
        staff = create(:user, :staff)
        create(:staff_space, user: staff, space: space)
        unavailability = create(:staff_unavailability, user: staff, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
        get unavailabilities_json_admin_calendar_index_path(id: space.id)
        row = response.parsed_body.flat_map { |group| group["unavailabilities"] }.find { |r| r["id"] == unavailability.id }
        expect(row["rrule"]).to eq(scenario[:sent])
      end

      it "is sent as Toronto wall-clock text by the staff unavailabilities feed" do
        staff = sign_in_as(:staff)
        unavailability = create(:staff_unavailability, user: staff, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
        get json_staff_unavailabilities_path
        row = response.parsed_body.find { |r| r["id"] == unavailability.id }
        expect(row["rrule"]).to eq(scenario[:sent])
      end

      it "is expanded by the server at the occurrences the staff calendar and the shifts API use" do
        expect(server_occurrences(stored, start)).to eq(scenario[:server])
      end
    end
  end

  # The browser reads an exclusion as one Toronto wall time, so the first and
  # the second 01:30 of the change day (05:30 and 06:30 UTC) are sent as the
  # same text. The calendar modal always sends the first one; the server's
  # expansion keeps only the first 01:30 of a series, so an exclusion stamped at
  # the second one removes nothing there.
  context "for an exclusion stamped at the second 01:30 of the change day" do
    let(:start) { zone.local(2027, 10, 31, 1, 30) }
    let(:stored) { "DTSTART:#{stamp(start)}\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20271107T063000Z" }

    it "is sent as the same text as an exclusion stamped at the first 01:30" do
      expect(RecurrenceRule.new(stored, start).in_toronto_time)
        .to eq("DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20271107T013000")
    end

    it "leaves the change-day occurrence in the server's expansion" do
      expect(server_occurrences(stored, start)).to eq(
        %w[2027-10-31T01:30:00-04:00 2027-11-07T01:30:00-04:00 2027-11-14T01:30:00-05:00 2027-11-21T01:30:00-05:00]
      )
    end
  end

  # An occurrence the modal excludes on the change day at 02:30 is stamped at
  # the instant 03:30 daylight time, which is sent as the wall time 03:30.
  context "for the skipped 02:30 occurrence excluded by the instant the modal sends" do
    let(:start) { zone.local(2027, 3, 7, 2, 30) }
    let(:stored) { "DTSTART:#{stamp(start)}\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20270314T073000Z" }

    it "is sent with the exclusion at 03:30" do
      expect(RecurrenceRule.new(stored, start).in_toronto_time)
        .to eq("DTSTART:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20270314T033000")
    end

    it "is left out of the server's expansion" do
      expect(server_occurrences(stored, start)).to eq(
        %w[2027-03-07T02:30:00-05:00 2027-03-21T02:30:00-04:00 2027-03-28T02:30:00-04:00]
      )
    end
  end
  # What each internal feed sends as the start and end of a stored series. The admin events feed and the staff
  # unavailabilities feed send instants with the Toronto offset; the admin unavailabilities feed sends Toronto wall
  # time without an offset. (Disagreement: the same series is described two ways. The window the page asks for is
  # ignored by all of them: every feed sends the whole series.)
  context "for the start and end each feed sends for a stored series" do
    let(:start) { zone.local(2027, 3, 7, 2, 30) }
    let(:stored) { "DTSTART:#{stamp(start)}\nRRULE:FREQ=WEEKLY;BYDAY=SU" }

    it "sends an instant with the offset from the admin events feed" do
      sign_in_as(:admin)
      event = create(:event, space: space, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
      get json_admin_events_path(id: space.id), params: { start: "2027-03-14T00:00:00-04:00", end: "2027-03-15T00:00:00-04:00" }
      row = response.parsed_body.flat_map { |group| group["events"] }.find { |r| r["id"] == "event-#{event.id}" }
      expect([row["start"], row["end"]]).to eq(%w[2027-03-07T02:30:00-05:00 2027-03-07T03:30:00-05:00])
    end

    it "sends Toronto wall time without an offset from the admin unavailabilities feed" do
      sign_in_as(:admin)
      staff = create(:user, :staff)
      create(:staff_space, user: staff, space: space)
      unavailability = create(:staff_unavailability, user: staff, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
      get unavailabilities_json_admin_calendar_index_path(id: space.id), params: { start: "2027-03-14T00:00:00-04:00", end: "2027-03-15T00:00:00-04:00" }
      row = response.parsed_body.flat_map { |group| group["unavailabilities"] }.find { |r| r["id"] == unavailability.id }
      expect([row["start"], row["end"]]).to eq(%w[2027-03-07T02:30:00 2027-03-07T03:30:00])
    end

    it "sends an instant with the offset from the staff unavailabilities feed" do
      staff = sign_in_as(:staff)
      unavailability = create(:staff_unavailability, user: staff, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
      get json_staff_unavailabilities_path, params: { start: "2027-03-14T00:00:00-04:00", end: "2027-03-15T00:00:00-04:00" }
      row = response.parsed_body.find { |r| r["id"] == unavailability.id }
      expect([row["start"], row["end"]]).to eq(%w[2027-03-07T02:30:00-05:00 2027-03-07T03:30:00-05:00])
    end
  end

  # A series that lasts across the change itself. The feeds send its length as one number of milliseconds, so the
  # browser adds it to the wall time; the server (RecurrenceExpansion) only lists start times and callers add the
  # length in real time. (Disagreement, named "timed series length across a clock change": the 01:00 occurrence of
  # 2027-03-14 ends at 03:00 on the page, one real hour later, and at 04:00 daylight time when measured in real
  # time. See rrule_feed_dst.test.js.)
  context "for a series whose length spans the clock change" do
    let(:start) { zone.local(2027, 3, 7, 1, 0) }
    let(:stored) { "DTSTART:#{stamp(start)}\nRRULE:FREQ=WEEKLY;BYDAY=SU" }

    it "is sent as two hours in milliseconds from the admin events feed" do
      sign_in_as(:admin)
      event = create(:event, space: space, start_time: start, end_time: start + 2.hours, recurrence_rule: stored)
      get json_admin_events_path(id: space.id)
      row = response.parsed_body.flat_map { |group| group["events"] }.find { |r| r["id"] == "event-#{event.id}" }
      expect(row["duration"]).to eq(7_200_000)
    end

    it "is expanded by the server with the clock-change occurrence at 01:00 standard time, ending at 04:00 in real time" do
      occurrences = RecurrenceExpansion.occurrences(stored, start, start, start + 27.days, 10).occurrences
      expect(occurrences.map(&:iso8601)).to eq(
        %w[2027-03-07T01:00:00-05:00 2027-03-14T01:00:00-05:00 2027-03-21T01:00:00-04:00 2027-03-28T01:00:00-04:00]
      )
      expect((occurrences.second + 2.hours).iso8601).to eq("2027-03-14T04:00:00-04:00")
    end
  end

  # The feeds that carry an imported calendar (ICS) next to the stored series: the admin unavailabilities feed (a
  # staff member's linked calendar), the admin imported calendars feed, the staff unavailabilities feed and the
  # public open hours feed. Each reads the file through CalendarHelper#ics_feed and sends the repeat rule as
  # floating Toronto text with a length in milliseconds. The ICS files are in spec/fixtures/files/ics and the exact
  # rows are pinned in spec/helpers/calendar_helper_ics_dst_spec.rb; here each feed is checked to send the same row.
  describe "imported calendars" do
    include ActiveSupport::Testing::TimeHelpers

    let(:feed_url) { "https://calendar.example.test/feed.ics" }
    let(:expected) { JSON.parse(Rails.root.join("spec/fixtures/files/ics/feed_events.json").read) }

    around { |example| travel_to(Time.utc(2027, 2, 1, 12)) { example.run } }

    def serve(fixture)
      body = Rails.root.join("spec/fixtures/files/ics/#{fixture}.ics").binread
      allow(IcsFetcher).to receive(:get).and_return(nil)
      allow(IcsFetcher).to receive(:get).with(feed_url, any_args).and_return(body)
    end

    # The rows each feed sends for the calendar at feed_url.
    def feed_rows(feed) = send("#{feed}_rows")

    def admin_imported_calendars_rows
      sign_in_as(:admin)
      create(:staff_needed_calendar, space: space, calendar_url: feed_url, name: "Hours", color: "#123456")
      get imported_calendars_json_admin_calendar_index_path(id: space.id)
      response.parsed_body.flat_map { |group| group["events"] }
    end

    def open_hours_rows
      create(:staff_needed_calendar, space: space, calendar_url: feed_url, name: "Hours", color: "#123456", role: "open_hours")
      get open_hours_path
      response.parsed_body.flat_map { |group| group["events"] }
    end

    def admin_unavailabilities_rows
      sign_in_as(:admin)
      staff = create(:user, :staff)
      create(:staff_space, user: staff, space: space)
      create(:staff_external_unavailability, user: staff, ics_url: feed_url)
      get unavailabilities_json_admin_calendar_index_path(id: space.id)
      response.parsed_body.flat_map { |group| group["unavailabilities"] }
    end

    def staff_unavailabilities_rows
      staff = sign_in_as(:staff)
      create(:staff_external_unavailability, user: staff, ics_url: feed_url)
      get json_staff_unavailabilities_path
      response.parsed_body
    end

    def sent(feed, fixture)
      serve(fixture)
      feed_rows(feed).to_h { |row| [row["id"], row.slice("rrule", "duration", "allDay")] }
    end

    def fixture_rows(fixture)
      expected.fetch(fixture).to_h { |row| [row["id"], row.slice("rrule", "duration", "allDay")] }
    end

    %i[admin_imported_calendars open_hours admin_unavailabilities staff_unavailabilities].each do |feed|
      context "in the #{feed.to_s.tr('_', ' ')} feed" do
        it "sends a Toronto-zone series over both clock changes as floating Toronto text" do
          rows = sent(feed, "toronto_tzid")
          expect(rows).to eq(fixture_rows("toronto_tzid"))
          expect(rows.dig("spring-0230@ics.test", "rrule")).to eq("DTSTART:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU")
          expect(rows.dig("fall-0130@ics.test", "rrule")).to eq("DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU")
          expect(rows.dig("spring-0230@ics.test", "duration")).to eq(3_600_000)
        end

        # Disagreement, named "calendar zone dropped": the file says Paris, the feed sends the Toronto wall time of
        # the first occurrence and the browser repeats that wall time in Toronto. Paris changes its clocks two weeks
        # after Toronto does, so for two weeks the real 09:00 in Paris is 04:00 in Toronto, not the 03:00 drawn.
        it "sends a Paris-zone series as the Toronto wall time of its first occurrence" do
          rows = sent(feed, "paris_tzid")
          expect(rows).to eq(fixture_rows("paris_tzid"))
          expect(rows.dig("paris-spring@ics.test", "rrule")).to eq("DTSTART:20270307T030000\nRRULE:FREQ=WEEKLY;BYDAY=SU")
        end

        # Disagreement, named "cancelled instance still sent": a cancelled instance is sent as an event of its own,
        # and a cancelled series is sent like any other.
        it "sends cancelled instances and cancelled series like any other event" do
          rows = sent(feed, "recurrence_id_cancelled")
          expect(rows).to eq(fixture_rows("recurrence_id_cancelled"))
          expect(rows.keys).to contain_exactly("cancelled@ics.test", "cancelled@ics.test_1805032800", "cancelled-series@ics.test")
        end
      end
    end
  end
end
