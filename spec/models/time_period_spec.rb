require "rails_helper"

RSpec.describe TimePeriod, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should have_many(:staff_availabilities) }
    end
  end

  describe "characterization (chunk 14)" do
    include ActiveSupport::Testing::TimeHelpers

    it "orders by start_date descending (default scope)" do
      old = TimePeriod.create!(name: "old", start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 4, 1))
      new = TimePeriod.create!(name: "new", start_date: Date.new(2027, 1, 1), end_date: Date.new(2027, 4, 1))
      expect(TimePeriod.all.to_a).to eq([new, old])
    end

    it "has no validations (blank dates are valid)" do
      expect(TimePeriod.new).to be_valid
    end

    describe ".current" do
      around { |ex| travel_to(Time.zone.local(2027, 2, 10, 12)) { ex.run } }

      it "is nil when no period covers today" do
        TimePeriod.create!(name: "past", start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 4, 1))
        expect(TimePeriod.current).to be_nil
      end

      it "returns the shortest period covering today, boundaries inclusive" do
        TimePeriod.create!(name: "year", start_date: Date.new(2027, 1, 1), end_date: Date.new(2027, 12, 31))
        term = TimePeriod.create!(name: "term", start_date: Date.new(2027, 1, 5), end_date: Date.new(2027, 2, 10))
        TimePeriod.create!(name: "next", start_date: Date.new(2027, 2, 11), end_date: Date.new(2027, 4, 1))
        expect(TimePeriod.current).to eq(term)
      end
    end

    # Uses Date.today (system zone: UTC in the devcontainer/CI), not Time.zone.today.
    describe ".current around local midnight" do
      around { |ex| travel_to(Time.zone.local(2027, 2, 10, 22)) { ex.run } } # 03:00Z on 02-11

      it "decides 'today' in the system zone, not the app zone" do
        skip "system zone is not UTC" unless Time.now.utc_offset.zero?
        evening = TimePeriod.create!(name: "toronto-today", start_date: Date.new(2027, 2, 10), end_date: Date.new(2027, 2, 10))
        utc_day = TimePeriod.create!(name: "utc-today", start_date: Date.new(2027, 2, 11), end_date: Date.new(2027, 2, 11))
        expect(Time.zone.today).to eq(Date.new(2027, 2, 10))
        expect(TimePeriod.current).to eq(utc_day)
        expect(TimePeriod.current).not_to eq(evening)
      end
    end
  end
end
