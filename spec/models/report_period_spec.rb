# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReportPeriod do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.find_zone("America/Toronto").local(2026, 6, 15, 12)) { example.run } }

  describe ".parse" do
    it "covers the first and last day as whole days in Toronto" do
      period = described_class.parse("2026-03-01", "2026-03-31")
      expect(period.window.begin).to eq(Time.find_zone("America/Toronto").local(2026, 3, 1))
      expect(period.window.end.to_f).to be_within(0.001).of(Time.find_zone("America/Toronto").local(2026, 4, 1).to_f - 0.000001)
    end

    it "keeps the clock-change days whole: 23 hours in spring, 25 in autumn" do
      spring = described_class.parse("2026-03-08", "2026-03-08").window
      autumn = described_class.parse("2026-11-01", "2026-11-01").window
      expect((spring.end - spring.begin).round / 3600.0).to eq(23.0)
      expect((autumn.end - autumn.begin).round / 3600.0).to eq(25.0)
    end

    it "includes a record made in the last second of the last day and excludes the next midnight" do
      window = described_class.parse("2026-12-31", "2026-12-31").window
      expect(window.cover?(Time.find_zone("America/Toronto").local(2026, 12, 31, 23, 59, 59))).to be true
      expect(window.cover?(Time.find_zone("America/Toronto").local(2027, 1, 1))).to be false
    end

    it "names the date that cannot be read, the start before the end" do
      expect { described_class.parse("abc", "def") }.to raise_error(described_class::Invalid, "Failed to parse start date")
      expect { described_class.parse("2026-03-01", nil) }.to raise_error(described_class::Invalid, "Failed to parse end date")
    end

    it "refuses an end before the start" do
      expect { described_class.parse("2026-03-02", "2026-03-01") }.to raise_error(described_class::Invalid, /before the start/)
    end

    it "allows one day, the earliest day and the end of next year, and nothing outside them" do
      expect { described_class.parse("2026-03-01", "2026-03-01") }.not_to raise_error
      expect { described_class.parse("2000-01-01", "2027-12-31") }.not_to raise_error
      expect { described_class.parse("1999-12-31", "2026-03-01") }.to raise_error(described_class::Invalid, /between/)
      expect { described_class.parse("2026-03-01", "2028-01-01") }.to raise_error(described_class::Invalid, /between/)
    end
  end

  describe ".semester" do
    it "gives the days of each term, in any letter case" do
      expect(described_class.semester("Winter", "2026").then { |p| [p.first_day, p.last_day] })
        .to eq([Date.new(2026, 1, 1), Date.new(2026, 4, 30)])
      expect(described_class.semester("summer", 2026).then { |p| [p.first_day, p.last_day] })
        .to eq([Date.new(2026, 5, 1), Date.new(2026, 8, 31)])
      expect(described_class.semester("FALL", "2026").then { |p| [p.first_day, p.last_day] })
        .to eq([Date.new(2026, 9, 1), Date.new(2026, 12, 31)])
    end

    it "refuses a missing or non-positive year and an unknown term" do
      expect { described_class.semester("fall", nil) }.to raise_error(described_class::Invalid, "Invalid year")
      expect { described_class.semester("spring", "2026") }.to raise_error(described_class::Invalid, "Invalid term")
    end
  end
end
