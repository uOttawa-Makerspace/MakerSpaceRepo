# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingSeries do
  def toronto(str)
    Time.use_zone("America/Toronto") { Time.zone.parse(str) }
  end

  def starts(first, end_date, frequency, hours: 1)
    first_start = toronto(first)
    described_class.new(first_start, first_start + hours.hours, Date.parse(end_date), frequency)
      .map { |start_time, _| start_time.strftime("%F %H:%M %Z") }
  end

  it "derives each monthly start from the first, clamped to the month end" do
    expect(starts("2027-01-31 10:00", "2027-06-30", "monthly")).to eq(
      ["2027-01-31 10:00 EST", "2027-02-28 10:00 EST", "2027-03-31 10:00 EDT",
       "2027-04-30 10:00 EDT", "2027-05-31 10:00 EDT", "2027-06-30 10:00 EDT"]
    )
  end

  it "clamps to February 29 in a leap year and returns to the 31st" do
    expect(starts("2028-01-31 10:00", "2028-03-31", "monthly").map { |s| s[0, 10] }).to eq(
      %w[2028-01-31 2028-02-29 2028-03-31]
    )
  end

  it "includes an occurrence that falls on the end date and excludes the next" do
    expect(starts("2027-02-03 10:00", "2027-02-17", "weekly").size).to eq(3)
    expect(starts("2027-02-03 10:00", "2027-02-16", "weekly").size).to eq(2)
  end

  it "includes a monthly occurrence on the end date, and not one a day later" do
    expect(starts("2027-01-15 10:00", "2027-03-15", "monthly").size).to eq(3)
    expect(starts("2027-01-15 10:00", "2027-03-14", "monthly").size).to eq(2)
  end

  it "yields the first occurrence even when the end date is not after it" do
    expect(starts("2027-02-03 10:00", "2027-02-03", "weekly").size).to eq(1)
    expect(starts("2027-02-03 10:00", "2027-02-01", "monthly").size).to eq(1)
  end

  it "treats any frequency other than weekly as monthly" do
    expect(starts("2027-02-03 10:00", "2027-04-03", "daily").map { |s| s[0, 10] }).to eq(
      %w[2027-02-03 2027-03-03 2027-04-03]
    )
  end

  it "keeps the wall-clock time across the spring DST start (weekly and monthly)" do
    expect(starts("2027-03-10 10:00", "2027-03-24", "weekly")).to eq(
      ["2027-03-10 10:00 EST", "2027-03-17 10:00 EDT", "2027-03-24 10:00 EDT"]
    )
    expect(starts("2027-02-20 10:00", "2027-04-20", "monthly")).to eq(
      ["2027-02-20 10:00 EST", "2027-03-20 10:00 EDT", "2027-04-20 10:00 EDT"]
    )
  end

  it "keeps the wall-clock time across the autumn DST end" do
    expect(starts("2027-10-31 10:00", "2027-11-14", "weekly")).to eq(
      ["2027-10-31 10:00 EDT", "2027-11-07 10:00 EST", "2027-11-14 10:00 EST"]
    )
  end

  it "ends each occurrence its first occurrence's duration after its start" do
    first_start = toronto("2027-01-31 10:00")
    series = described_class.new(first_start, first_start + 90.minutes, Date.new(2027, 3, 31), "monthly")
    expect(series.map { |s, e| e - s }.uniq).to eq([90.minutes])
  end

  it "is lazy-safe: first(n) stops without walking the series" do
    first_start = toronto("2027-01-31 10:00")
    series = described_class.new(first_start, first_start + 1.hour, Date.new(2099, 1, 1), "weekly")
    expect(series.first(2).size).to eq(2)
  end
end
