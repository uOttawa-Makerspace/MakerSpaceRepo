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
end
