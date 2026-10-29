# frozen_string_literal: true

require "rails_helper"

# RecurrenceExpansion across the America/Toronto DST changes (D-SP29). A
# DAILY/WEEKLY/MONTHLY/YEARLY rule repeats a wall-clock time:
#   spring-forward 2027-03-14: 02:30 does not exist and moves forward to 03:30 EDT;
#   fall-back 2026-11-01: 01:30 happens twice and is listed once, at the first
#   (EDT) instant. IceCube alone lists it twice and counts both against COUNT.
RSpec.describe RecurrenceExpansion do
  let(:zone) { ActiveSupport::TimeZone["Eastern Time (US & Canada)"] }

  def local(*parts) = zone.local(*parts)
  def starts(rule, start, from, to, limit = 500) = described_class.occurrences(rule, start, from, to, limit).occurrences.map(&:iso8601)

  describe "spring-forward (2027-03-14)" do
    it "moves a nonexistent 02:30 forward to 03:30 EDT on the day of the change only" do
      expect(starts("RRULE:FREQ=DAILY;COUNT=3", local(2027, 3, 13, 2, 30), local(2027, 3, 1), local(2027, 4, 1)))
        .to eq(%w[2027-03-13T02:30:00-05:00 2027-03-14T03:30:00-04:00 2027-03-15T02:30:00-04:00])
    end

    it "keeps a weekly 10:00 event at 10:00 local on both sides" do
      expect(starts("RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=3", local(2027, 3, 7, 10), local(2027, 3, 1), local(2027, 4, 1)))
        .to eq(%w[2027-03-07T10:00:00-05:00 2027-03-14T10:00:00-04:00 2027-03-21T10:00:00-04:00])
    end
  end

  describe "fall-back (2026-11-01)" do
    it "lists a daily 01:30 event once on the day of the change, at 01:30 EDT, and keeps COUNT" do
      expect(starts("RRULE:FREQ=DAILY;COUNT=4", local(2026, 10, 31, 1, 30), local(2026, 10, 1), local(2026, 12, 1)))
        .to eq(%w[2026-10-31T01:30:00-04:00 2026-11-01T01:30:00-04:00 2026-11-02T01:30:00-05:00 2026-11-03T01:30:00-05:00])
    end

    it "does not let the repeated hour use up a weekly COUNT" do
      expect(starts("RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=3", local(2026, 10, 25, 1, 30), local(2026, 10, 1), local(2026, 12, 1)))
        .to eq(%w[2026-10-25T01:30:00-04:00 2026-11-01T01:30:00-04:00 2026-11-08T01:30:00-05:00])
    end

    it "applies COUNT from the series start when the window starts later" do
      expect(starts("RRULE:FREQ=DAILY;COUNT=4", local(2026, 10, 31, 1, 30), local(2026, 11, 2), local(2026, 12, 1)))
        .to eq(%w[2026-11-02T01:30:00-05:00 2026-11-03T01:30:00-05:00])
    end

    it "drops the repeated 01:30 without a COUNT too, and honours UNTIL" do
      expect(starts("RRULE:FREQ=DAILY;UNTIL=20261102T120000Z", local(2026, 10, 31, 1, 30), local(2026, 10, 1), local(2026, 12, 1)))
        .to eq(%w[2026-10-31T01:30:00-04:00 2026-11-01T01:30:00-04:00 2026-11-02T01:30:00-05:00])
    end

    it "keeps 02:30 (not repeated in Toronto) and 10:00 at the same local time" do
      expect(starts("RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=2", local(2026, 10, 25, 2, 30), local(2026, 10, 1), local(2026, 12, 1)))
        .to eq(%w[2026-10-25T02:30:00-04:00 2026-11-01T02:30:00-05:00])
      expect(starts("RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=2", local(2026, 10, 25, 10), local(2026, 10, 1), local(2026, 12, 1)))
        .to eq(%w[2026-10-25T10:00:00-04:00 2026-11-01T10:00:00-05:00])
    end

    it "keeps a series that itself starts at the second (EST) 01:30" do
      second = local(2026, 11, 1, 1, 30) + 1.hour
      expect(second.iso8601).to eq("2026-11-01T01:30:00-05:00")
      expect(starts("RRULE:FREQ=DAILY;COUNT=2", second, local(2026, 10, 1), local(2026, 12, 1)))
        .to eq(%w[2026-11-01T01:30:00-05:00 2026-11-02T01:30:00-05:00])
    end

    it "leaves an HOURLY legacy rule's elapsed hours alone (both 01:00 hours are real)" do
      expect(starts("RRULE:FREQ=HOURLY;COUNT=3", local(2026, 11, 1, 0, 0), local(2026, 10, 1), local(2026, 12, 1)))
        .to eq(%w[2026-11-01T00:00:00-04:00 2026-11-01T01:00:00-04:00 2026-11-01T01:00:00-05:00])
    end
  end

  it "still stops at the limit and reports truncation" do
    result = described_class.occurrences("RRULE:FREQ=DAILY", local(2026, 10, 25, 1, 30), local(2026, 10, 25), local(2026, 12, 1), 3)
    expect(result.occurrences.map(&:iso8601)).to eq(%w[2026-10-25T01:30:00-04:00 2026-10-26T01:30:00-04:00 2026-10-27T01:30:00-04:00])
    expect(result.truncated).to be(true)
  end
end
