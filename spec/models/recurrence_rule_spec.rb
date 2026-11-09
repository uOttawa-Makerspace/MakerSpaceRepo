# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurrenceRule do
  let(:weekly) { "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T150000Z" }
  let(:series_start) { Time.utc(2027, 3, 1, 15) }

  def rule(text = weekly) = described_class.new(text, series_start)

  describe ".parse" do
    it "splits the rule, the start (as UTC) and the other lines" do
      rrule, dtstart, rest = described_class.parse("DTSTART:20270505T130000Z\nRRULE:FREQ=DAILY\nEXDATE:20270506T130000Z")
      expect(rrule).to eq("FREQ=DAILY")
      expect(dtstart).to eq(Time.utc(2027, 5, 5, 13))
      expect(rest).to eq(["EXDATE:20270506T130000Z"])
    end

    it "returns nil for a missing start or rule" do
      expect(described_class.parse("EXDATE:20270506T130000Z")).to eq([nil, nil, ["EXDATE:20270506T130000Z"]])
      expect(described_class.parse(nil)).to eq([nil, nil, []])
    end
  end

  describe "#without_occurrence" do
    it "excludes the instant and keeps the earlier exclusions" do
      expect(rule.without_occurrence(Time.utc(2027, 3, 15, 15))).to eq(
        "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270315T150000Z\nEXDATE:20270308T150000Z"
      )
    end

    it "starts a rule stored without a DTSTART at the series start" do
      expect(rule("RRULE:FREQ=DAILY").without_occurrence(Time.utc(2027, 3, 2, 15))).to eq(
        "DTSTART:20270301T150000Z\nRRULE:FREQ=DAILY\nEXDATE:20270302T150000Z"
      )
    end
  end

  describe "#ending_before" do
    it "ends the series a day before the instant, replacing an earlier end" do
      expect(rule("DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20271201T000000Z")
               .ending_before(Time.utc(2027, 3, 15, 15))).to eq(
                 "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20270314T150000Z"
               )
    end
  end

  describe "#with_exdate" do
    it "adds the instant as one more exclusion and leaves the rest as written" do
      expect(rule.with_exdate(Time.utc(2027, 3, 22, 15))).to eq("#{weekly}\nEXDATE:20270322T150000Z")
    end

    it "returns the rule untouched when the rule or the instant is blank" do
      expect(rule.with_exdate(nil)).to eq(weekly)
      expect(rule(nil).with_exdate(Time.utc(2027, 3, 22, 15))).to be_nil
      expect(rule("").with_exdate(Time.utc(2027, 3, 22, 15))).to eq("")
    end
  end

  describe "#moved_to_time_of" do
    it "keeps the start date and the exclusions and takes the new time of day for the same repeat" do
      expect(rule.moved_to_time_of("DTSTART:20270322T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO")).to eq(
        "DTSTART:20270301T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T150000Z"
      )
    end

    it "takes the new rule as it is when the repeat changed" do
      changed = "DTSTART:20270322T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=TU"
      expect(rule.moved_to_time_of(changed)).to eq(changed)
    end

    it "takes the new rule as it is when either rule has no start" do
      expect(rule.moved_to_time_of("RRULE:FREQ=WEEKLY;BYDAY=MO")).to eq("RRULE:FREQ=WEEKLY;BYDAY=MO")
      expect(rule("RRULE:FREQ=WEEKLY;BYDAY=MO").moved_to_time_of(weekly)).to eq(weekly)
    end
  end
end
