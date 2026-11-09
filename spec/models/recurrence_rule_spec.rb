# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurrenceRule do
  let(:weekly) { "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T150000Z" }
  let(:series_start) { Time.utc(2027, 3, 1, 15) }

  def rule(text = weekly) = described_class.new(text, series_start)

  it "reads a rule with leading spaces and CRLF line ends, and one with no lines" do
    expect(rule("  DTSTART:20270505T130000Z\r\n  RRULE:FREQ=DAILY\r\n").without_occurrence(Time.utc(2027, 5, 6, 13)))
      .to eq("DTSTART:20270505T130000Z\nRRULE:FREQ=DAILY\nEXDATE:20270506T130000Z")
    expect(rule(nil).with_time_from(weekly)).to eq(weekly)
  end

  # Times arrive as UTC from the controllers, but a zoned time gives the same stamps.
  describe "with a time in another zone" do
    let(:toronto) { Time.utc(2027, 3, 15, 15).in_time_zone("America/Toronto") }

    it "writes its UTC stamp" do
      expect(rule.without_occurrence(toronto)).to include("EXDATE:20270315T150000Z")
      expect(rule.ending_before(toronto)).to include("UNTIL=20270314T150000Z")
      expect(rule.appending_exdate(toronto)).to end_with("EXDATE:20270315T150000Z")
      expect(rule.appending_exdate(Time.new(2027, 3, 15, 16, 0, 0, "+01:00"))).to end_with("EXDATE:20270315T150000Z")
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

  describe "#appending_exdate" do
    it "adds the instant as one more exclusion and leaves the rest as written" do
      expect(rule.appending_exdate(Time.utc(2027, 3, 22, 15))).to eq("#{weekly}\nEXDATE:20270322T150000Z")
    end

    it "returns the rule untouched when the rule or the instant is blank" do
      expect(rule.appending_exdate(nil)).to eq(weekly)
      expect(rule(nil).appending_exdate(Time.utc(2027, 3, 22, 15))).to be_nil
      expect(rule("").appending_exdate(Time.utc(2027, 3, 22, 15))).to eq("")
    end
  end

  describe "#with_time_from" do
    it "keeps the start date and the exclusions and takes the new time of day for the same repeat" do
      expect(rule.with_time_from("DTSTART:20270322T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO")).to eq(
        "DTSTART:20270301T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T150000Z"
      )
    end

    it "takes the new rule as it is when the repeat changed" do
      changed = "DTSTART:20270322T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=TU"
      expect(rule.with_time_from(changed)).to eq(changed)
    end

    it "takes the new rule as it is when either rule has no start" do
      expect(rule.with_time_from("RRULE:FREQ=WEEKLY;BYDAY=MO")).to eq("RRULE:FREQ=WEEKLY;BYDAY=MO")
      expect(rule("RRULE:FREQ=WEEKLY;BYDAY=MO").with_time_from(weekly)).to eq(weekly)
    end
  end
end
