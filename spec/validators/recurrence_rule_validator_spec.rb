# frozen_string_literal: true

require "rails_helper"

# D-SP28: recurrence_rule is blank or an RRULE with FREQ DAILY/WEEKLY/MONTHLY/YEARLY.
RSpec.describe RecurrenceRuleValidator do
  let(:model) do
    Class.new do
      include ActiveModel::Model
      attr_accessor :recurrence_rule
      validates :recurrence_rule, recurrence_rule: true
      def self.name = "Thing"
    end
  end

  def errors_for(rule)
    thing = model.new(recurrence_rule: rule)
    thing.valid?
    thing.errors[:recurrence_rule]
  end

  # exactly what rrule.js toString() produces from the two forms
  VALIDATOR_FORM_RULES = {
    "daily" => "DTSTART:20270301T150000Z\nRRULE:FREQ=DAILY",
    "daily until" => "DTSTART:20270301T150000Z\nRRULE:FREQ=DAILY;UNTIL=20270331T235959Z",
    "daily with days" => "DTSTART:20270301T150000Z\nRRULE:FREQ=DAILY;BYDAY=MO,TU",
    "weekly" => "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR",
    "weekly until" => "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;UNTIL=20270331T235959Z;BYDAY=MO",
    "weekly count" => "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;COUNT=4;BYDAY=MO",
    "monthly" => "DTSTART:20270301T150000Z\nRRULE:FREQ=MONTHLY",
    "monthly until byday" => "DTSTART:20270301T150000Z\nRRULE:FREQ=MONTHLY;UNTIL=20271231T235959Z;BYDAY=MO",
    "monthly count" => "DTSTART:20270301T150000Z\nRRULE:FREQ=MONTHLY;COUNT=6",
    "yearly" => "DTSTART:20270301T150000Z\nRRULE:FREQ=YEARLY",
    "with EXDATE" => "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20270308T150000Z",
    "without DTSTART" => "RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4",
    "UNTIL without Z" => "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;UNTIL=20270331T235959;BYDAY=MO",
    "TZID DTSTART" => "DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO",
    "CRLF" => "DTSTART:20270301T150000Z\r\nRRULE:FREQ=WEEKLY;BYDAY=MO\r\nEXDATE:20270308T150000Z\r\n",
    "following editor rewritten UNTIL" => "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20270314T150000Z\nEXDATE:20270308T150000Z",
    "leading whitespace" => "  DTSTART:20270301T150000Z\n  RRULE:FREQ=DAILY"
  }.freeze

  VALIDATOR_FORM_RULES.each do |name, rule|
    it "accepts #{name}" do
      expect(errors_for(rule)).to eq([])
    end
  end

  it "accepts nil and blank" do
    expect(errors_for(nil)).to eq([])
    expect(errors_for("")).to eq([])
    expect(errors_for("  \n")).to eq([])
  end

  %w[SECONDLY MINUTELY HOURLY].each do |freq|
    it "rejects FREQ=#{freq} in every shape" do
      [
        "RRULE:FREQ=#{freq}",
        "DTSTART:20270301T150000Z\nRRULE:FREQ=#{freq};COUNT=5",
        "DTSTART:20270301T150000Z\nRRULE:FREQ=#{freq};UNTIL=20270331T235959Z",
        "RRULE:INTERVAL=2;FREQ=#{freq}", "FREQ=#{freq}"
      ].each do |rule|
        expected = rule.include?("RRULE:") ? RecurrenceRuleValidator::MESSAGE : RecurrenceRuleValidator::UNPARSEABLE
        expect(errors_for(rule)).to eq([expected]), rule.inspect
      end
    end
  end

  it "rejects a sub-daily rule hidden behind a valid one" do
    expect(errors_for("RRULE:FREQ=DAILY\nRRULE:FREQ=MINUTELY")).to eq([RecurrenceRuleValidator::MESSAGE])
  end

  it "rejects a repeated FREQ even when the last one is allowed" do
    ["RRULE:FREQ=DAILY;FREQ=MINUTELY", "RRULE:FREQ=MINUTELY;FREQ=DAILY", "RRULE:FREQ=DAILY;FREQ=DAILY"].each do |rule|
      expect(errors_for(rule)).not_to be_empty, rule.inspect
    end
  end

  it "rejects the first-FREQ bypass with the message for the sub-daily frequency actually applied" do
    expect(errors_for("DTSTART:20270301T150000Z\nRRULE:FREQ=DAILY;FREQ=MINUTELY")).not_to be_empty
  end

  %w[BYHOUR=0,1 BYMINUTE=0,30 BYSECOND=0 BYSETPOS=1].each do |part|
    it "rejects #{part}" do
      expect(errors_for("DTSTART:20270301T150000Z\nRRULE:FREQ=DAILY;#{part}")).to eq([RecurrenceRuleValidator::MESSAGE])
      expect(errors_for("RRULE:FREQ=DAILY;byhour=1;#{part}")).not_to be_empty
    end
  end

  it "rejects a bare rule without an RRULE: line (the controllers' parser cannot read it)" do
    expect(errors_for("FREQ=DAILY;COUNT=3")).to eq([RecurrenceRuleValidator::UNPARSEABLE])
    expect(errors_for("DTSTART:20270301T150000Z\nFREQ=DAILY")).to eq([RecurrenceRuleValidator::UNPARSEABLE])
  end

  it "caps the length" do
    long = "DTSTART:20270301T150000Z\nRRULE:FREQ=DAILY\n" + ("EXDATE:20270308T150000Z\n" * 100)
    expect(long.length).to be > 2000
    expect(errors_for(long)).to eq([RecurrenceRuleValidator::TOO_LONG])
  end

  it "reads leading whitespace and CRLF the same as the controllers' parser" do
    rule = "  DTSTART:20270301T150000Z\r\n  RRULE:FREQ=DAILY;COUNT=2\r\n"
    rrule, dtstart, = ApplicationController.helpers.parse_rrule_and_dtstart(rule)
    expect(rrule).to eq("FREQ=DAILY;COUNT=2")
    expect(dtstart).to eq(Time.utc(2027, 3, 1, 15))
    expect(RecurrenceExpansion.rule_body(rule)).to eq("FREQ=DAILY;COUNT=2")
  end

  it "rejects a missing FREQ and garbage" do
    ["COUNT=3", "RRULE:BYDAY=MO", "garbage", "NOT A RULE", "INVALID_RULE", "FREQ=", "FREQ=FORTNIGHTLY", "freq=daily",
     "DTSTART:20270301T150000Z", "RRULE:", "FREQ=DAILY;COUNT=abc;INTERVAL=x"].each do |rule|
      expect(errors_for(rule)).to eq([RecurrenceRuleValidator::UNPARSEABLE]).or(eq([RecurrenceRuleValidator::MESSAGE])), rule.inspect
      expect(errors_for(rule)).not_to be_empty, rule.inspect
    end
  end

  it "is applied by Event and StaffUnavailability" do
    expect(Event.validators_on(:recurrence_rule).map(&:class)).to include(described_class)
    expect(StaffUnavailability.validators_on(:recurrence_rule).map(&:class)).to include(described_class)
  end
end
