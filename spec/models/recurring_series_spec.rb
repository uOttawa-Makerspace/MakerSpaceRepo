# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringSeries do
  let(:zone) { ActiveSupport::TimeZone["America/Toronto"] }

  def at(*parts) = zone.local(*parts)

  def series(rule, starts_at, ends_at, **) = described_class.new(rule: rule, starts_at: starts_at, ends_at: ends_at, **)

  def starting(series, from, to, limit: 500) = series.occurrences_starting_in(from..to, limit: limit)

  def overlapping(series, from, to, limit: 500) = series.occurrences_overlapping(from..to, limit: limit)

  def times(result) = result.occurrences.map { |o| o.starts_at.iso8601 }

  describe "the spring-forward Sunday (2027-03-14)" do
    let(:shift) { series("RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=3", at(2027, 3, 7, 1), at(2027, 3, 7, 3)) }

    it "keeps the real length of a timed series across the change" do
      found = starting(shift, at(2027, 3, 1), at(2027, 4, 1)).occurrences
      expect(found.map { |o| (o.ends_at - o.starts_at).to_i }).to eq([7200, 7200, 7200])
      expect(found[1].starts_at.iso8601).to eq("2027-03-14T01:00:00-05:00")
      expect(found[1].ends_at.iso8601).to eq("2027-03-14T04:00:00-04:00")
    end

    it "moves a nonexistent 02:30 forward to 03:30" do
      daily = series("RRULE:FREQ=DAILY;COUNT=3", at(2027, 3, 13, 2, 30), at(2027, 3, 13, 3, 30))
      expect(times(starting(daily, at(2027, 3, 1), at(2027, 4, 1))))
        .to eq(%w[2027-03-13T02:30:00-05:00 2027-03-14T03:30:00-04:00 2027-03-15T02:30:00-04:00])
    end

    it "advances an all-day series by calendar days, so it stays all-day on the change day" do
      all_day = series("RRULE:FREQ=DAILY;COUNT=3", at(2027, 3, 13), at(2027, 3, 14))
      found = starting(all_day, at(2027, 3, 1), at(2027, 4, 1)).occurrences
      expect(found.map(&:all_day)).to all(be(true))
      expect(found.map { |o| o.ends_at.iso8601 }).to eq(%w[2027-03-14T00:00:00-05:00 2027-03-15T00:00:00-04:00 2027-03-16T00:00:00-04:00])
    end
  end

  describe "the fall-back Sunday (2027-11-07)" do
    it "lists a repeated 01:30 once, at its first instant, and keeps COUNT" do
      daily = series("RRULE:FREQ=DAILY;COUNT=3", at(2027, 11, 6, 1, 30), at(2027, 11, 6, 2, 30))
      expect(times(starting(daily, at(2027, 11, 1), at(2027, 12, 1))))
        .to eq(%w[2027-11-06T01:30:00-04:00 2027-11-07T01:30:00-04:00 2027-11-08T01:30:00-05:00])
    end

    it "keeps the real length of a timed series across the change" do
      weekly = series("RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=2", at(2027, 10, 31, 0, 30), at(2027, 10, 31, 2, 30))
      second = starting(weekly, at(2027, 10, 1), at(2027, 12, 1)).occurrences.last
      expect(second.ends_at.iso8601).to eq("2027-11-07T01:30:00-05:00")
    end

    it "advances an all-day series by calendar days (25 hours on the change day)" do
      all_day = series("RRULE:FREQ=DAILY;COUNT=3", at(2027, 11, 6), at(2027, 11, 7))
      found = starting(all_day, at(2027, 11, 1), at(2027, 12, 1)).occurrences
      expect(found.map { |o| o.ends_at.iso8601 }).to eq(%w[2027-11-07T00:00:00-04:00 2027-11-08T00:00:00-05:00 2027-11-09T00:00:00-05:00])
    end
  end

  describe "windows" do
    let(:overnight) { series("RRULE:FREQ=DAILY", at(2027, 5, 1, 22), at(2027, 5, 2, 6)) }

    it "returns an occurrence that began before the window when it overlaps it" do
      from = at(2027, 5, 10, 3)
      expect(times(overlapping(overnight, from, at(2027, 5, 10, 4)))).to eq(%w[2027-05-09T22:00:00-04:00])
      expect(times(starting(overnight, from, at(2027, 5, 10, 4)))).to eq([])
    end

    it "does not return an occurrence that ended before the window or starts after it" do
      expect(overlapping(overnight, at(2027, 5, 10, 6), at(2027, 5, 10, 22)).occurrences).to be_empty
    end

    it "carries the original start and no override" do
      occurrence = starting(overnight, at(2027, 5, 10), at(2027, 5, 11)).occurrences.first
      expect([occurrence.original_start, occurrence.override]).to eq([occurrence.starts_at, nil])
    end
  end

  describe "COUNT and exclusions" do
    it "counts an excluded occurrence against COUNT" do
      rule = "DTSTART:20270501T100000Z\nRRULE:FREQ=DAILY;COUNT=3\nEXDATE:20270502T100000Z"
      daily = series(rule, at(2027, 5, 1, 6), at(2027, 5, 1, 7))
      expect(times(starting(daily, at(2027, 4, 1), at(2027, 6, 1)))).to eq(%w[2027-05-01T06:00:00-04:00 2027-05-03T06:00:00-04:00])
    end

    it "takes exclusions as instants: UTC, Toronto wall time, and several in one line" do
      rule = "RRULE:FREQ=DAILY;COUNT=5\nEXDATE:20270501T100000Z,20270502T060000\nEXDATE;TZID=America/Toronto:20270503T060000"
      daily = series(rule, at(2027, 5, 1, 6), at(2027, 5, 1, 7))
      expect(times(starting(daily, at(2027, 4, 1), at(2027, 6, 1)))).to eq(%w[2027-05-04T06:00:00-04:00 2027-05-05T06:00:00-04:00])
    end

    it "applies COUNT from the series start when the window opens later" do
      daily = series("RRULE:FREQ=DAILY;COUNT=4", at(2027, 5, 1, 6), at(2027, 5, 1, 7))
      expect(times(starting(daily, at(2027, 5, 3), at(2027, 6, 1)))).to eq(%w[2027-05-03T06:00:00-04:00 2027-05-04T06:00:00-04:00])
    end
  end

  describe "limits" do
    let(:daily) { series("RRULE:FREQ=DAILY", at(2027, 5, 1, 6), at(2027, 5, 1, 7)) }

    it "stops at the limit and says it was cut short, for both kinds of window" do
      [method(:starting), method(:overlapping)].each do |read|
        result = read.call(daily, at(2027, 5, 1), at(2027, 8, 1), limit: 3)
        expect([result.occurrences.size, result.truncated]).to eq([3, true])
      end
    end

    it "is not truncated when the occurrences fit exactly" do
      result = starting(daily, at(2027, 5, 1), at(2027, 5, 3, 12), limit: 3)
      expect([result.occurrences.size, result.truncated]).to eq([3, false])
    end
  end

  describe "rule parts the library handles" do
    def monthly(rule, start) = series("RRULE:#{rule}", start, start + 1.hour)

    it "honours BYSETPOS=-1 over a set of weekdays (the last weekday of the month)" do
      last = monthly("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", at(2027, 2, 26, 9))
      expect(times(starting(last, at(2027, 2, 1), at(2027, 6, 1))).map { |t| t[0, 10] }).to eq(%w[2027-02-26 2027-03-31 2027-04-30 2027-05-31])
    end

    it "honours BYSETPOS=2 with one weekday (the second Sunday), on both sides of the clock change" do
      second = monthly("FREQ=MONTHLY;BYDAY=SU;BYSETPOS=2", at(2027, 2, 14, 2, 30))
      expect(times(starting(second, at(2027, 2, 1), at(2027, 5, 1))))
        .to eq(%w[2027-02-14T02:30:00-05:00 2027-03-14T03:30:00-04:00 2027-04-11T02:30:00-04:00])
    end

    it "honours BYSETPOS=1 (the first Sunday, in the repeated hour on 2027-11-07)" do
      first = monthly("FREQ=MONTHLY;BYDAY=SU;BYSETPOS=1", at(2027, 10, 3, 1, 30))
      expect(times(starting(first, at(2027, 10, 1), at(2027, 12, 31))))
        .to eq(%w[2027-10-03T01:30:00-04:00 2027-11-07T01:30:00-04:00 2027-12-05T01:30:00-05:00])
    end

    it "honours several BYSETPOS positions at once" do
      both = monthly("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1", at(2027, 3, 1, 9))
      expect(times(starting(both, at(2027, 3, 1), at(2027, 5, 1))).map { |t| t[0, 10] }).to eq(%w[2027-03-01 2027-03-31 2027-04-01 2027-04-30])
    end

    it "honours BYWEEKNO" do
      yearly = series("RRULE:FREQ=YEARLY;BYWEEKNO=20;BYDAY=MO;COUNT=2", at(2027, 5, 17, 9), at(2027, 5, 17, 10))
      expect(times(starting(yearly, at(2027, 1, 1), at(2029, 1, 1))).map { |t| t[0, 10] }).to eq(%w[2027-05-17 2028-05-15])
    end

    it "includes the last day of a date UNTIL and of an all-day series" do
      timed = series("RRULE:FREQ=DAILY;UNTIL=20270303", at(2027, 3, 1, 22), at(2027, 3, 1, 23))
      expect(times(starting(timed, at(2027, 3, 1), at(2027, 4, 1))).size).to eq(3)
      all_day = series("RRULE:FREQ=DAILY;UNTIL=20270315", at(2027, 3, 13), at(2027, 3, 14))
      expect(times(starting(all_day, at(2027, 3, 1), at(2027, 4, 1)))).to eq(%w[2027-03-13T00:00:00-05:00 2027-03-14T00:00:00-05:00 2027-03-15T00:00:00-04:00])
    end

    it "reads an UNTIL without Z as Toronto wall time and one with Z as that instant" do
      bare = series("RRULE:FREQ=DAILY;UNTIL=20270302T090000", at(2027, 3, 1, 9), at(2027, 3, 1, 10))
      zulu = series("RRULE:FREQ=DAILY;UNTIL=20270302T140000Z", at(2027, 3, 1, 9), at(2027, 3, 1, 10))
      expect(times(starting(bare, at(2027, 3, 1), at(2027, 4, 1))).size).to eq(2)
      expect(times(starting(zulu, at(2027, 3, 1), at(2027, 4, 1))).size).to eq(2)
    end

    it "takes a VALUE=DATE exclusion as that day's midnight" do
      all_day = series("RRULE:FREQ=DAILY;COUNT=3\nEXDATE;VALUE=DATE:20270314", at(2027, 3, 13), at(2027, 3, 14))
      expect(times(starting(all_day, at(2027, 3, 1), at(2027, 4, 1)))).to eq(%w[2027-03-13T00:00:00-05:00 2027-03-15T00:00:00-04:00])
    end

    it "keeps elapsed time for an HOURLY rule stored before validation, across the fall-back hour" do
      hourly = series("RRULE:FREQ=HOURLY;COUNT=3", at(2027, 11, 7, 0), at(2027, 11, 7, 0, 30))
      expect(times(starting(hourly, at(2027, 11, 1), at(2027, 12, 1))))
        .to eq(%w[2027-11-07T00:00:00-04:00 2027-11-07T01:00:00-04:00 2027-11-07T01:00:00-05:00])
    end

    it "raises for a rule the library cannot read" do
      expect { starting(series("RRULE:FREQ=DAILY;COUNT=abc", at(2027, 3, 1), at(2027, 3, 2)), at(2027, 3, 1), at(2027, 4, 1)) }
        .to raise_error(RRule::InvalidRRule)
    end
  end

  describe "a series that starts at the second 01:30 of the fall-back night" do
    let(:second) { at(2027, 11, 7, 1, 30) + 1.hour }

    it "keeps its own start as the first occurrence, then repeats 01:30 standard time" do
      expect(second.iso8601).to eq("2027-11-07T01:30:00-05:00")
      daily = series("RRULE:FREQ=DAILY;COUNT=2", second, second + 1.hour)
      expect(times(starting(daily, at(2027, 11, 1), at(2027, 12, 1)))).to eq(%w[2027-11-07T01:30:00-05:00 2027-11-08T01:30:00-05:00])
    end

    it "keeps the start when the window opens after it" do
      daily = series("RRULE:FREQ=DAILY;COUNT=3", second, second + 1.hour)
      expect(times(starting(daily, at(2027, 11, 8), at(2027, 12, 1)))).to eq(%w[2027-11-08T01:30:00-05:00 2027-11-09T01:30:00-05:00])
    end
  end

  describe "a series in another zone" do
    it "repeats the wall time of its own zone" do
      paris = ActiveSupport::TimeZone["Europe/Paris"]
      weekly = series("RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=3", paris.local(2027, 3, 21, 9), paris.local(2027, 3, 21, 10))
      expect(times(starting(weekly, at(2027, 3, 1), at(2027, 5, 1))).map { |t| t[0, 19] }).to eq(%w[2027-03-21T09:00:00 2027-03-28T09:00:00 2027-04-04T09:00:00])
    end
  end

  describe ".for_record" do
    it "reads an event's rule, start and end" do
      event = build(:event, start_time: at(2027, 3, 13, 9), end_time: at(2027, 3, 13, 10), recurrence_rule: "FREQ=DAILY;COUNT=2")
      expect(times(starting(described_class.for_record(event), at(2027, 3, 1), at(2027, 4, 1))))
        .to eq(%w[2027-03-13T09:00:00-05:00 2027-03-14T09:00:00-04:00])
    end

    it "reads a staff unavailability the same way" do
      unavailability = build(:staff_unavailability, start_time: at(2027, 3, 13, 9), end_time: at(2027, 3, 13, 10), recurrence_rule: "FREQ=DAILY;COUNT=2")
      expect(starting(described_class.for_record(unavailability), at(2027, 3, 1), at(2027, 4, 1)).occurrences.size).to eq(2)
    end
  end
end
