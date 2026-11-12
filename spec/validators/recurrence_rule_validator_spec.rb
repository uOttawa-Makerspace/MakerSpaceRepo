# frozen_string_literal: true

require "rails_helper"

# recurrence_rule is blank or an RRULE with FREQ DAILY/WEEKLY/MONTHLY/YEARLY.
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

  it "rejects a sub-daily rule hidden behind a valid one (a second RRULE line is refused)" do
    expect(errors_for("RRULE:FREQ=DAILY\nRRULE:FREQ=MINUTELY")).to eq([I18n.t("errors.calendar.rule_one_line")])
  end

  it "rejects a repeated FREQ even when the last one is allowed" do
    ["RRULE:FREQ=DAILY;FREQ=MINUTELY", "RRULE:FREQ=MINUTELY;FREQ=DAILY", "RRULE:FREQ=DAILY;FREQ=DAILY"].each do |rule|
      expect(errors_for(rule)).not_to be_empty, rule.inspect
    end
  end

  it "rejects a rule whose first FREQ is allowed but a later one is sub-daily, with the sub-daily message" do
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

  it "reads leading whitespace and CRLF the same as the series edits' parser" do
    rule = "  DTSTART:20270301T150000Z\r\n  RRULE:FREQ=DAILY;COUNT=2\r\n"
    expect(RecurrenceRule.new(rule, nil).without_occurrence(Time.utc(2027, 3, 2, 15))).to eq(
      "DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=DAILY;COUNT=2\nEXDATE:20270302T150000Z"
    )
    expect(RecurrenceRule.rule_body(rule)).to eq("FREQ=DAILY;COUNT=2")
  end

  it "accepts a rule whose start is a UTC stamp or Toronto wall-clock time" do
    expect(errors_for("DTSTART:20270301T150000Z\nRRULE:FREQ=DAILY;COUNT=2")).to eq([])
    expect(errors_for("DTSTART;TZID=America/Toronto:20270301T100000\nRRULE:FREQ=DAILY;COUNT=2")).to eq([])
  end

  it "accepts a floating start (no Z, no zone)" do
    expect(errors_for("DTSTART:20270301T100000\nRRULE:FREQ=DAILY;COUNT=2")).to eq([])
  end

  it "accepts a start line with no stamp, which the series edits read as no start" do
    expect(errors_for("DTSTART:\nRRULE:FREQ=DAILY")).to eq([])
  end

  it "rejects a start line that the series edits cannot read" do
    [
      "DTSTART;TZID=Nowhere/Land:20270301T100000\nRRULE:FREQ=DAILY",
      "DTSTART:garbage\nRRULE:FREQ=DAILY",
      "DTSTART:20271345T250000Z\nRRULE:FREQ=DAILY",
      "DTSTART:20270301T150000Z\nDTSTART:garbage\nRRULE:FREQ=DAILY"
    ].each do |rule|
      expect(errors_for(rule)).to eq([RecurrenceRuleValidator::UNPARSEABLE]), rule.inspect
    end
  end

  it "rejects out-of-range numbers the repeat library would accept" do
    ["FREQ=DAILY;BYYEARDAY=400", "FREQ=WEEKLY;BYMONTHDAY=0", "FREQ=YEARLY;BYMONTH=13", "FREQ=MONTHLY;BYMONTHDAY=1,x", "FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO"].each do |body|
      expect(errors_for("RRULE:#{body}")).to eq([RecurrenceRuleValidator::UNPARSEABLE]), body
    end
  end

  it "accepts BYDAY ordinals as RFC 5545 allows them for each frequency" do
    ["FREQ=MONTHLY;BYDAY=2MO", "FREQ=MONTHLY;BYDAY=-1FR,+2TU", "FREQ=MONTHLY;BYDAY=5MO,-5SU", "FREQ=YEARLY;BYDAY=53MO", "FREQ=YEARLY;BYDAY=-53MO,20TU",
     "FREQ=YEARLY;BYMONTH=3;BYDAY=5MO", "FREQ=WEEKLY;BYDAY=MO,SU", "FREQ=DAILY;BYDAY=MO,TU", "FREQ=DAILY;WKST=SU"].each do |body|
      expect(errors_for("RRULE:#{body}")).to eq([]), body
    end
  end

  it "refuses an ordinal that does not fit the frequency, without raising (the repeat library raises on some)" do
    ["FREQ=MONTHLY;BYDAY=53MO", "FREQ=MONTHLY;BYDAY=6MO", "FREQ=MONTHLY;BYDAY=-6FR", "FREQ=YEARLY;BYMONTH=3;BYDAY=53MO", "FREQ=YEARLY;BYMONTH=3;BYDAY=6MO",
     "FREQ=WEEKLY;BYDAY=2MO", "FREQ=WEEKLY;BYDAY=-1FR", "FREQ=DAILY;BYDAY=1MO"].each do |body|
      expect { expect(errors_for("RRULE:#{body}")).to eq([RecurrenceRuleValidator::UNPARSEABLE]) }.not_to raise_error, body
    end
  end

  it "refuses a rule with more than one RRULE line, without expanding any of them" do
    many = "DTSTART:20270301T150000Z\n#{Array.new(40) { 'RRULE:FREQ=DAILY;BYMONTH=2;BYMONTHDAY=30' }.join("\n")}"
    taken = 0
    allow_any_instance_of(RRule::Frequency).to receive(:advance).and_wrap_original { |m, *a| taken += 1; m.call(*a) }
    expect(errors_for(many)).to eq([I18n.t("errors.calendar.rule_one_line")])
    expect(errors_for("RRULE:FREQ=DAILY\nRRULE:FREQ=WEEKLY;BYDAY=MO")).to eq([I18n.t("errors.calendar.rule_one_line")])
    expect(taken).to eq(0)
    expect(I18n.t("errors.calendar.rule_one_line", locale: :fr)).not_to eq(I18n.t("errors.calendar.rule_one_line"))
  end

  it "rejects a BYDAY or WKST that is not a weekday with a valid ordinal" do
    ["FREQ=WEEKLY;BYDAY=XX", "FREQ=MONTHLY;BYDAY=54MO", "FREQ=MONTHLY;BYDAY=0MO", "FREQ=MONTHLY;BYDAY=-54FR", "FREQ=WEEKLY;BYDAY=mo",
     "FREQ=WEEKLY;BYDAY=", "FREQ=WEEKLY;BYDAY=MO,,TU", "FREQ=WEEKLY;WKST=XX", "FREQ=WEEKLY;WKST=MO,TU"].each do |body|
      expect(errors_for("RRULE:#{body}")).to eq([RecurrenceRuleValidator::UNPARSEABLE]), body
    end
  end

  it "rejects a negative or out-of-range BYMONTH, which cannot count from the end" do
    ["FREQ=YEARLY;BYMONTH=-1", "FREQ=YEARLY;BYMONTH=0", "FREQ=YEARLY;BYMONTH=13", "FREQ=YEARLY;BYMONTH=1,-2"].each do |body|
      expect(errors_for("RRULE:#{body}")).to eq([RecurrenceRuleValidator::UNPARSEABLE]), body
    end
  end

  it "rejects lower-case and unknown rule part names" do
    ["freq=daily", "FREQ=DAILY;until=20270331", "FREQ=DAILY;byday=MO", "FREQ=DAILY;X-FOO=1", "FREQ=DAILY;BYWKST=1", "FREQ=DAILY;;COUNT=2"].each do |body|
      expect(errors_for("RRULE:#{body}")).to eq([RecurrenceRuleValidator::UNPARSEABLE]), body
    end
  end

  it "rejects a rule that repeats a part name, so the last value cannot hide the first" do
    ["FREQ=DAILY;BYMONTH=99;BYMONTH=2", "FREQ=DAILY;COUNT=1;COUNT=9999999999", "FREQ=DAILY;FREQ=WEEKLY", "FREQ=WEEKLY;BYDAY=XX;BYDAY=MO"].each do |body|
      expect(errors_for("RRULE:#{body}")).to eq([RecurrenceRuleValidator::UNPARSEABLE]), body
    end
  end

  describe "a rule that never has an occurrence" do
    let(:never) { I18n.t("errors.calendar.rule_never_repeats") }
    let(:start) { RecurrenceRule::ZONE.local(2027, 1, 31, 9) }

    def steps
      count = 0
      allow_any_instance_of(RRule::Frequency).to receive(:advance).and_wrap_original do |original, *args|
        count += 1
        original.call(*args)
      end
      yield
      count
    end

    it "is refused, with a message in English and French" do
      ["FREQ=DAILY;BYMONTH=2;BYMONTHDAY=30", "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30", "FREQ=YEARLY;BYMONTH=4;BYMONTHDAY=31",
       "FREQ=MONTHLY;BYMONTH=2;BYMONTHDAY=31;INTERVAL=2", "FREQ=DAILY;BYMONTH=2;BYMONTHDAY=30;COUNT=3"].each do |body|
        expect(errors_for("RRULE:#{body}")).to eq([never]), body
      end
      expect(never).to include("never")
      I18n.with_locale(:fr) { expect(errors_for("RRULE:FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30")).to eq([I18n.t("errors.calendar.rule_never_repeats")]) }
      expect(I18n.t("errors.calendar.rule_never_repeats", locale: :fr)).not_to eq(never)
    end

    it "is judged from the series start, which the rule can depend on" do
      expect(described_class.error_for("RRULE:FREQ=MONTHLY;BYMONTH=2", start)).to eq(never) # the 31st of February
      expect(described_class.error_for("RRULE:FREQ=MONTHLY;BYMONTH=2", RecurrenceRule::ZONE.local(2027, 1, 15, 9))).to be_nil
    end

    it "accepts rules that repeat rarely or have already ended" do
      ["FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29", "FREQ=YEARLY;INTERVAL=9", "FREQ=MONTHLY;BYDAY=5MO", "FREQ=WEEKLY;INTERVAL=5;BYDAY=MO",
       "FREQ=DAILY;UNTIL=20200101T000000Z", "FREQ=DAILY;COUNT=1"].each do |body|
        expect(described_class.error_for("RRULE:#{body}", start)).to be_nil, body
      end
    end

    it "takes a few steps for a normal rule, and a bounded number for a rule that never matches" do
      expect(steps { described_class.error_for("RRULE:FREQ=WEEKLY;BYDAY=MO,WE", start) }).to be <= 3
      expect(steps { described_class.error_for("RRULE:FREQ=DAILY", start) }).to be <= 3
      expect(steps { described_class.error_for("RRULE:FREQ=DAILY;BYMONTH=2;BYMONTHDAY=30", start) }).to be <= 12 * 366
    end
  end

  it "does not hide an error that is not about the rule's text" do
    allow(RRule::Rule).to receive(:new).and_raise("bug")
    expect { errors_for("RRULE:FREQ=DAILY") }.to raise_error("bug")
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
