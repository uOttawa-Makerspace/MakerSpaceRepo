# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurrenceRule do
  let(:weekly) { "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T150000Z" }
  let(:series_start) { Time.utc(2027, 3, 1, 15) }

  def rule(text = weekly) = described_class.new(text, series_start)

  it "reads a rule with leading spaces and CRLF line ends, and one with no lines" do
    expect(rule("  DTSTART:20270505T130000Z\r\n  RRULE:FREQ=DAILY\r\n").without_occurrence(Time.utc(2027, 5, 6, 13)))
      .to eq("DTSTART;TZID=America/Toronto:20270505T090000\nRRULE:FREQ=DAILY\nEXDATE:20270506T130000Z")
    expect(rule(nil).with_time_from(weekly, at: series_start)).to eq(weekly)
  end

  describe "reading the start" do
    def start_line(text) = rule(text).without_occurrence(Time.utc(2030, 1, 1)).lines.first.chomp

    it "reads a UTC start, a Toronto start and a start with no zone (Toronto) as the same instant" do
      expected = "DTSTART;TZID=America/Toronto:20270310T100000"
      expect(start_line("DTSTART:20270310T150000Z\nRRULE:FREQ=DAILY")).to eq(expected)
      expect(start_line("DTSTART;TZID=America/Toronto:20270310T100000\nRRULE:FREQ=DAILY")).to eq(expected)
      expect(start_line("DTSTART:20270310T100000\nRRULE:FREQ=DAILY")).to eq(expected)
    end

    it "reads a start in another named zone in that zone" do
      expect(start_line("DTSTART;TZID=Europe/Paris:20270310T160000\nRRULE:FREQ=DAILY")).to eq("DTSTART;TZID=America/Toronto:20270310T100000")
    end

    it "takes the series start for a rule with no start or an empty one" do
      # the series start is 2027-03-01 15:00Z, 10:00 in Toronto
      expect(start_line("RRULE:FREQ=DAILY")).to eq("DTSTART;TZID=America/Toronto:20270301T100000")
      expect(start_line("DTSTART:\nRRULE:FREQ=DAILY")).to eq("DTSTART;TZID=America/Toronto:20270301T100000")
    end
  end

  describe "#in_toronto_time" do
    it "starts at the series start in Toronto time and writes each exclusion in Toronto time" do
      text = "DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T150000Z,20270315T140000Z"
      expect(rule(text).in_toronto_time).to eq(
        "DTSTART:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T100000,20270315T100000"
      )
    end

    it "leaves an exclusion already in wall-clock time as it is" do
      expect(rule("RRULE:FREQ=DAILY\nEXDATE:20270302T100000").in_toronto_time)
        .to eq("DTSTART:20270301T100000\nRRULE:FREQ=DAILY\nEXDATE:20270302T100000")
    end
  end

  it "edits a rule stored with a Toronto start from the same start as one with a UTC start" do
    toronto = "DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T150000Z"
    expect(rule(toronto).without_occurrence(Time.utc(2027, 3, 15, 14))).to eq(rule.without_occurrence(Time.utc(2027, 3, 15, 14)))
    expect(rule(toronto).ending_before(Time.utc(2027, 3, 15, 14))).to eq(rule.ending_before(Time.utc(2027, 3, 15, 14)))
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

  describe "#dialog_fields" do
    it "is the frequency, the weekdays and the Toronto date of the last day" do
      expect(rule("DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;UNTIL=20270316T035959Z;BYDAY=MO,WE").dialog_fields)
        .to eq(frequency: "WEEKLY", weekdays: %w[MO WE], until: "2027-03-15")
    end

    JSON.parse(Rails.root.join("spec/fixtures/calendar_dst_cases.json").read)["untilDates"].each do |c|
      it "is the Toronto date of a series written to end on #{c['label']}" do
        expect(rule("RRULE:FREQ=DAILY;UNTIL=#{c['until']}").dialog_fields[:until]).to eq(c["date"])
      end
    end

    it "reads a bare rule body, a date-only or wall-clock UNTIL, and none" do
      expect(rule("FREQ=DAILY;UNTIL=20270320").dialog_fields).to eq(frequency: "DAILY", weekdays: [], until: "2027-03-20")
      expect(rule("RRULE:FREQ=MONTHLY;UNTIL=20270320T235959").dialog_fields).to eq(frequency: "MONTHLY", weekdays: [], until: "2027-03-20")
      expect(rule.dialog_fields).to eq(frequency: "WEEKLY", weekdays: ["MO"], until: nil)
    end
  end

  describe "#without_occurrence" do
    it "excludes the instant and keeps the earlier exclusions" do
      expect(rule.without_occurrence(Time.utc(2027, 3, 15, 15))).to eq(
        "DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270315T150000Z\nEXDATE:20270308T150000Z"
      )
    end

    it "starts a rule stored without a DTSTART at the series start" do
      expect(rule("RRULE:FREQ=DAILY").without_occurrence(Time.utc(2027, 3, 2, 15))).to eq(
        "DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=DAILY\nEXDATE:20270302T150000Z"
      )
    end
  end

  describe "#ending_before" do
    it "ends the series a day before the instant, replacing an earlier end" do
      expect(rule("DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20271201T000000Z")
               .ending_before(Time.utc(2027, 3, 15, 15))).to eq(
                 "DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20270314T150000Z"
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
    it "keeps the start date and the exclusions and takes the Toronto time of day of the new start for the same repeat" do
      # 18:30Z on 2027-03-22 is 14:30 daylight time; 14:30 on 2027-03-01 is 19:30Z
      expect(rule.with_time_from("DTSTART:20270322T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO", at: Time.utc(2027, 3, 1, 19, 30))).to eq(
        "DTSTART;TZID=America/Toronto:20270301T143000\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T150000Z"
      )
    end

    it "keeps the Toronto date of a late-evening start" do
      # 23:30 on Monday 2027-03-01 is 04:30Z on the Tuesday; moved to 22:00
      late = "DTSTART:20270302T043000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO"
      expect(rule(late).with_time_from("DTSTART;TZID=America/Toronto:20270322T220000\nRRULE:FREQ=WEEKLY;BYDAY=MO", at: Time.utc(2027, 3, 2, 3)))
        .to eq("DTSTART;TZID=America/Toronto:20270301T220000\nRRULE:FREQ=WEEKLY;BYDAY=MO")
    end

    it "takes the new rule as it is when the repeat changed" do
      changed = "DTSTART:20270322T183000Z\nRRULE:FREQ=WEEKLY;BYDAY=TU"
      expect(rule.with_time_from(changed, at: series_start)).to eq(changed)
    end

    it "keeps the series' own time when the new start is the series start, whatever time the new rule starts at" do
      expect(rule.with_time_from("DTSTART;TZID=America/Toronto:20270322T033000\nRRULE:FREQ=WEEKLY;BYDAY=MO", at: series_start))
        .to eq("DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T150000Z")
    end

    it "takes the new rule as it is when either rule has no start" do
      expect(rule.with_time_from("RRULE:FREQ=WEEKLY;BYDAY=MO", at: series_start)).to eq("RRULE:FREQ=WEEKLY;BYDAY=MO")
      expect(rule("RRULE:FREQ=WEEKLY;BYDAY=MO").with_time_from(weekly, at: series_start)).to eq(weekly)
    end
  end
end
