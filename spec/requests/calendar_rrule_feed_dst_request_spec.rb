# frozen_string_literal: true

require "rails_helper"

# What the calendar feeds send for weekly series across the America/Toronto
# clock changes of 2027 (forward Sunday 2027-03-14 at 02:00, back Sunday
# 2027-11-07 at 02:00). The admin events feed sends a repeat rule string
# that the browser expands with @fullcalendar/rrule in the Toronto zone; the
# same strings are drawn in spec/javascript/calendars/rrule_feed_dst.test.js.
# The unavailabilities feeds asked for a range send the occurrences of the
# server's own expansion (RecurringSeries, also used by the staff calendar and
# the shifts API), so they draw what the server stores. The imported calendar
# feeds do the same.
RSpec.describe "Repeat rules sent by the calendar feeds across clock changes", type: :request do
  include SpacesSpecHelpers

  let(:zone) { ActiveSupport::TimeZone["America/Toronto"] }
  let!(:space) { create(:space) }

  def stamp(time) = time.utc.strftime("%Y%m%dT%H%M%SZ")

  def server_occurrences(rule, start)
    series_starts(rule, start, start, start + 27.days, 10).map(&:iso8601)
  end

  # The four weeks from the series start, as the calendar pages ask for them.
  def four_weeks(start) = { start: start.iso8601, end: (start + 27.days + 2.hours).iso8601 }

  def staff_feed_starts(start, stored)
    staff = sign_in_as(:staff)
    create(:staff_unavailability, user: staff, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
    get json_staff_unavailabilities_path, params: four_weeks(start)
    response.parsed_body.map { |row| row["start"] }
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

      it "is sent by the admin unavailabilities feed for a range as the server's occurrences" do
        sign_in_as(:admin)
        staff = create(:user, :staff)
        create(:staff_space, user: staff, space: space)
        create(:staff_unavailability, user: staff, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
        get unavailabilities_json_admin_calendar_index_path(id: space.id), params: four_weeks(start)
        rows = response.parsed_body.flat_map { |group| group["unavailabilities"] }
        expect(rows.map { |row| row["start"] }).to eq(scenario[:server])
        expect(rows.map { |row| Time.iso8601(row.dig("extendedProps", "occurrenceStart")) }).to eq(scenario[:server].map { |t| Time.iso8601(t) })
      end

      it "is sent by the staff unavailabilities feed as the server's occurrences" do
        expect(staff_feed_starts(start, stored)).to eq(scenario[:server])
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

    it "leaves the change-day occurrence in the staff unavailabilities feed" do
      expect(staff_feed_starts(start, stored)).to eq(server_occurrences(stored, start))
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

    it "is left out of the staff unavailabilities feed" do
      expect(staff_feed_starts(start, stored)).to eq(server_occurrences(stored, start))
    end
  end
  # What each internal feed sends as the start and end of a stored series asked for the week of the change. The
  # admin events feed sends the series' own first start (the page repeats it); the unavailabilities feeds send the
  # change-day occurrence, at the time the server moves the skipped 02:30 to, with the Toronto offset.
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

    it "sends the change-day occurrence with the offset from the admin unavailabilities feed" do
      sign_in_as(:admin)
      staff = create(:user, :staff)
      create(:staff_space, user: staff, space: space)
      unavailability = create(:staff_unavailability, user: staff, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
      get unavailabilities_json_admin_calendar_index_path(id: space.id), params: { start: "2027-03-14T00:00:00-05:00", end: "2027-03-15T00:00:00-04:00" }
      row = response.parsed_body.flat_map { |group| group["unavailabilities"] }.sole
      expect(row.values_at("id", "start", "end")).to eq(["#{unavailability.id}@#{Time.utc(2027, 3, 14, 7, 30).to_i}",
                                                         "2027-03-14T03:30:00-04:00", "2027-03-14T04:30:00-04:00"])
    end

    it "sends the change-day occurrence with the offset from the staff unavailabilities feed" do
      staff = sign_in_as(:staff)
      unavailability = create(:staff_unavailability, user: staff, start_time: start, end_time: start + 1.hour, recurrence_rule: stored)
      get json_staff_unavailabilities_path, params: { start: "2027-03-14T00:00:00-05:00", end: "2027-03-15T00:00:00-04:00" }
      row = response.parsed_body.sole
      expect(row.values_at("id", "start", "end")).to eq(["#{unavailability.id}@#{Time.utc(2027, 3, 14, 7, 30).to_i}",
                                                         "2027-03-14T03:30:00-04:00", "2027-03-14T04:30:00-04:00"])
    end
  end

  # A series that lasts across the change itself. The feeds send its length as one number of milliseconds, so the
  # browser adds it to the wall time; the server (RecurringSeries) only lists start times and callers add the
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

    it "is sent by the staff unavailabilities feed ending two real hours later, at 04:00 daylight time" do
      staff = sign_in_as(:staff)
      create(:staff_unavailability, user: staff, start_time: start, end_time: start + 2.hours, recurrence_rule: stored)
      get json_staff_unavailabilities_path, params: { start: "2027-03-14T00:00:00-05:00", end: "2027-03-15T00:00:00-04:00" }
      expect(response.parsed_body.sole.values_at("start", "end")).to eq(%w[2027-03-14T01:00:00-05:00 2027-03-14T04:00:00-04:00])
    end

    it "is expanded by the server with the clock-change occurrence at 01:00 standard time, ending at 04:00 in real time" do
      occurrences = series_starts(stored, start, start, start + 27.days, 10)
      expect(occurrences.map(&:iso8601)).to eq(
        %w[2027-03-07T01:00:00-05:00 2027-03-14T01:00:00-05:00 2027-03-21T01:00:00-04:00 2027-03-28T01:00:00-04:00]
      )
      expect((occurrences.second + 2.hours).iso8601).to eq("2027-03-14T04:00:00-04:00")
    end
  end

  # The feeds that carry an imported calendar (ICS) next to the stored series: the admin unavailabilities feed (a
  # staff member's linked calendar) and the staff unavailabilities feed. Each reads the file and sends the occurrences
  # in the range asked for, as the server expands them. The ICS files are in spec/fixtures/files/ics. (The admin
  # imported calendars feed and the public open hours feed also send occurrences:
  # spec/requests/imported_calendar_feeds_request_spec.rb.)
  describe "imported calendars" do
    include ActiveSupport::Testing::TimeHelpers

    let(:feed_url) { "https://calendar.example.test/feed.ics" }

    around { |example| travel_to(Time.utc(2027, 2, 1, 12)) { example.run } }

    def serve(fixture)
      body = Rails.root.join("spec/fixtures/files/ics/#{fixture}.ics").binread
      allow(IcsFetcher).to receive(:get).and_return(nil)
      allow(IcsFetcher).to receive(:get).with(feed_url, any_args).and_return(body)
    end

    def admin_unavailabilities_rows(range)
      sign_in_as(:admin)
      staff = create(:user, :staff)
      create(:staff_space, user: staff, space: space)
      create(:staff_external_unavailability, user: staff, ics_url: feed_url)
      get unavailabilities_json_admin_calendar_index_path(id: space.id), params: range
      response.parsed_body.flat_map { |group| group["unavailabilities"] }
    end

    def staff_unavailabilities_rows(range)
      staff = sign_in_as(:staff)
      create(:staff_external_unavailability, user: staff, ics_url: feed_url)
      get json_staff_unavailabilities_path, params: range
      response.parsed_body
    end

    # The unavailabilities feeds send the occurrences of the imported series in the range, in the zone of the file,
    # as the server expands them.
    %i[admin_unavailabilities staff_unavailabilities].each do |feed|
      context "in the #{feed.to_s.tr('_', ' ')} feed" do
        define_method(:starts) do |fixture, range|
          serve(fixture)
          send("#{feed}_rows", range).map { |row| [row["id"], row["start"]] }
        end

        it "sends a Toronto-zone series at its occurrences, the skipped 02:30 at 03:30" do
          expect(starts("toronto_tzid", start: "2027-03-07T00:00:00-05:00", end: "2027-03-15T00:00:00-04:00")).to eq([
            ["spring-0230@ics.test@#{Time.utc(2027, 3, 7, 7, 30).to_i}", "2027-03-07T02:30:00-05:00"],
            ["spring-0230@ics.test@#{Time.utc(2027, 3, 14, 7, 30).to_i}", "2027-03-14T03:30:00-04:00"]
          ])
        end

        it "sends a Paris-zone series at 09:00 Paris time, 04:00 in Toronto while only Toronto has changed its clocks" do
          expect(starts("paris_tzid", start: "2027-03-14T00:00:00-05:00", end: "2027-03-29T00:00:00-04:00").map(&:last))
            .to eq(%w[2027-03-14T04:00:00-04:00 2027-03-21T04:00:00-04:00 2027-03-28T03:00:00-04:00])
        end

        it "leaves out the cancelled instance and the cancelled series" do
          expect(starts("recurrence_id_cancelled", start: "2027-03-07T00:00:00-05:00", end: "2027-03-22T00:00:00-04:00").map(&:last))
            .to eq(%w[2027-03-07T10:00:00-05:00 2027-03-21T10:00:00-04:00])
        end
      end
    end
  end
end
