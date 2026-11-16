# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reschedulable do
  let(:zone) { Time.zone }
  let(:first) { zone.local(2027, 10, 31, 1, 30) }
  let(:series) do
    build(:staff_unavailability, start_time: first, end_time: first + 1.hour, recurrence_rule: "DTSTART:20271031T053000Z\nRRULE:FREQ=WEEKLY;BYDAY=SU")
  end
  let(:posted) { [Time.utc(2027, 11, 7, 5, 30), Time.utc(2027, 11, 7, 7, 30)] }

  describe "#times_after_update" do
    it "gives the posted times" do
      expect(series.times_after_update(*posted, keep: false)).to eq(posted)
    end

    it "gives its own times when they are kept" do
      expect(series.times_after_update(*posted, keep: true)).to eq([first, first + 1.hour])
    end

    it "gives a series its date at the posted clock time for the posted length" do
      expect(series.times_after_update(*posted, keep: false, series: true)).to eq([first, first + 2.hours])
    end

    it "reads the clock time in Toronto, where 01:02Z on 2027-05-06 is the evening before" do
      result = series.times_after_update(Time.utc(2020, 1, 1, 13, 45, 30), Time.utc(2020, 1, 1, 14, 45, 30), keep: false, series: true)
      expect(result.first).to eq(zone.local(2027, 10, 31, 8, 45, 30))
      expect(result.first.time_zone.name).to eq("America/Toronto")
    end
  end

  describe "#occurrence_after_update" do
    it "excludes the posted date at the series' clock time and takes the posted times" do
      expect(series.occurrence_after_update(Time.utc(2027, 11, 14, 17, 0), Time.utc(2027, 11, 14, 18, 0), keep: false))
        .to eq([zone.local(2027, 11, 14, 1, 30), Time.utc(2027, 11, 14, 17, 0), Time.utc(2027, 11, 14, 18, 0)])
    end

    it "gives the real occurrence nearest the posted start when the times are kept" do
      expect(series.occurrence_after_update(*posted, keep: true)).to eq([Time.utc(2027, 11, 7, 5, 30), Time.utc(2027, 11, 7, 5, 30), Time.utc(2027, 11, 7, 6, 30)])
    end

    it "takes the posted times when the kept occurrence is no longer in the series" do
      gone = build(:staff_unavailability, start_time: first, end_time: first + 1.hour, recurrence_rule: "#{series.recurrence_rule}\nEXDATE:20271107T053000Z")
      expect(gone.occurrence_after_update(*posted, keep: true)).to eq([zone.local(2027, 11, 7, 1, 30), *posted])
    end
  end
end
