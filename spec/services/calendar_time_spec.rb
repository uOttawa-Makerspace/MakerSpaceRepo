# frozen_string_literal: true

require "rails_helper"

# FullCalendar's allDay flag: the span starts at a local
# midnight and ends at the next local midnight, in the app zone. That day is
# 23h on spring-forward (2027-03-14) and 25h on fall-back (2026-11-01).
RSpec.describe CalendarTime do
  let(:zone) { ActiveSupport::TimeZone["Eastern Time (US & Canada)"] }

  def local(*parts) = zone.local(*parts)
  def all_day?(from, to) = described_class.all_day?(from, to)

  it "is true for midnight to the next midnight, including both DST change days" do
    expect(all_day?(local(2027, 5, 5), local(2027, 5, 6))).to be(true)
    expect(all_day?(local(2027, 3, 14), local(2027, 3, 15))).to be(true)  # 23h
    expect(all_day?(local(2026, 11, 1), local(2026, 11, 2))).to be(true)  # 25h
  end

  it "accepts UTC instants and compares in the app zone" do
    expect(all_day?(Time.utc(2027, 5, 5, 4), Time.utc(2027, 5, 6, 4))).to be(true)
    expect(all_day?(Time.utc(2027, 5, 5), Time.utc(2027, 5, 6))).to be(false) # 20:00 to 20:00 local
  end

  it "is false for a 23h span that is not midnight to midnight (Sun 03:30 EDT to Mon 02:30)" do
    expect(all_day?(local(2027, 3, 14, 3, 30), local(2027, 3, 15, 2, 30))).to be(false)
  end

  it "is false for 01:30 EST on the fall-back day to 01:30 the next day" do
    second = local(2026, 11, 1, 1, 30) + 1.hour
    expect(second.iso8601).to eq("2026-11-01T01:30:00-05:00")
    expect(all_day?(second, local(2026, 11, 2, 1, 30))).to be(false)
  end

  it "is false for a 24h span that does not start at midnight" do
    expect(all_day?(local(2027, 5, 5, 9), local(2027, 5, 6, 9))).to be(false)
  end

  it "is false for a multi-day midnight-to-midnight span (unchanged)" do
    expect(all_day?(local(2027, 5, 5), local(2027, 5, 7))).to be(false)
  end
end
