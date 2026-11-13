# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reschedulable do
  let(:zone) { Time.zone }
  let(:first) { zone.local(2027, 10, 31, 1, 30) }
  let(:series) { build(:staff_unavailability, start_time: first, end_time: first + 1.hour) }

  describe ".combine_date_and_time" do
    it "keeps the Toronto date and takes the Toronto clock time" do
      # 01:02Z on 2027-05-06 is the evening of 2027-05-05 in Toronto; 13:45Z in January is 8:45 standard time
      result = described_class.combine_date_and_time(Time.utc(2027, 5, 6, 1, 2, 3), Time.utc(2020, 1, 1, 13, 45, 30))
      expect(result).to eq(Time.utc(2027, 5, 5, 12, 45, 30))
      expect(result.time_zone.name).to eq("America/Toronto")
    end
  end

  describe "#times_after_update" do
    let(:posted) { [Time.utc(2027, 11, 7, 5, 30), Time.utc(2027, 11, 7, 7, 30)] }

    it "gives the posted times" do
      expect(series.times_after_update(*posted, keep: false)).to eq(posted)
    end

    it "gives its own times when they are kept" do
      expect(series.times_after_update(*posted, keep: true)).to eq([first, first + 1.hour])
    end
  end

  describe "#times_after_update for a series" do
    let(:posted) { [Time.utc(2027, 11, 7, 5, 30), Time.utc(2027, 11, 7, 7, 30)] }

    it "gives its date at the posted clock time for the posted length" do
      expect(series.times_after_update(*posted, keep: false, series: true)).to eq([first, first + 2.hours])
    end

    it "gives its own times when they are kept" do
      expect(series.times_after_update(*posted, keep: true, series: true)).to eq([first, first + 1.hour])
    end
  end

  describe "#occurrence_start_on" do
    it "gives the posted date at its own clock time" do
      expect(series.occurrence_start_on(Time.utc(2027, 11, 14, 17, 0))).to eq(zone.local(2027, 11, 14, 1, 30))
    end
  end
end
