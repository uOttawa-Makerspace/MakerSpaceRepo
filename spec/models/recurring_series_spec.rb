# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringSeries do
  let(:zone) { ActiveSupport::TimeZone["America/Toronto"] }

  def at(*parts) = zone.local(*parts)

  def series(rule, starts_at, ends_at, **) = described_class.new(rule: rule, starts_at: starts_at, ends_at: ends_at, **)

  def starting(series, from, to, limit: 500) = series.occurrences_starting_in(from..to, limit: limit)

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

  describe "#occurrences_in (a calendar window)" do
    def window(from, to) = CalendarWindow.new(from, to)

    it "keeps an occurrence that started before the window and reaches into it" do
      nightly = series("RRULE:FREQ=DAILY", at(2027, 3, 1, 22), at(2027, 3, 2, 2))
      found = nightly.occurrences_in(window(at(2027, 3, 5, 1), at(2027, 3, 5, 23)))
      expect(found.map { |o| o.starts_at.iso8601 }).to eq(%w[2027-03-04T22:00:00-05:00 2027-03-05T22:00:00-05:00])
    end

    it "moves the skipped 02:30 forward and leaves out an exclusion at the instant the dialog posts" do
      weekly = series("RRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20270321T063000Z", at(2027, 3, 7, 2, 30), at(2027, 3, 7, 3, 30))
      found = weekly.occurrences_in(window(at(2027, 3, 8), at(2027, 3, 29)))
      expect(found.map { |o| o.starts_at.iso8601 }).to eq(%w[2027-03-14T03:30:00-04:00 2027-03-28T02:30:00-04:00])
    end

    it "keeps an all-day occurrence of the day before the window, which reaches into it" do
      all_day = series("RRULE:FREQ=DAILY", at(2027, 3, 1), at(2027, 3, 2))
      found = all_day.occurrences_in(window(at(2027, 3, 14, 12), at(2027, 3, 14, 13)))
      expect(found.map { |o| o.starts_at.iso8601 }).to eq(%w[2027-03-14T00:00:00-05:00])
    end

    it "is the one occurrence of a series with no rule, when it overlaps the window" do
      once = series(nil, at(2027, 3, 14, 9), at(2027, 3, 14, 10))
      expect(once.occurrences_in(window(at(2027, 3, 14), at(2027, 3, 15))).map(&:starts_at)).to eq([at(2027, 3, 14, 9)])
      expect(once.occurrences_in(window(at(2027, 3, 15), at(2027, 3, 16)))).to eq([])
    end
  end

  describe "Occurrence#overlaps?" do
    def occurrence(from, to) = described_class::Occurrence.new(starts_at: from, ends_at: to, all_day: false)

    it "is true for occurrences that share some time, and not for ones that only touch" do
      event = occurrence(at(2027, 3, 17, 10), at(2027, 3, 17, 11))
      expect(occurrence(at(2027, 3, 17, 10, 30), at(2027, 3, 17, 12)).overlaps?(event)).to be(true)
      expect(occurrence(at(2027, 3, 17, 11), at(2027, 3, 17, 12)).overlaps?(event)).to be(false)
    end

    it "is false for an occurrence of no length (a moment), even inside the other" do
      moment = occurrence(at(2027, 3, 17, 10, 30), at(2027, 3, 17, 10, 30))
      expect(moment.overlaps?(occurrence(at(2027, 3, 17, 10), at(2027, 3, 17, 11)))).to be(false)
    end
  end

  describe "Occurrence#feed_row" do
    it "sends the times with their Toronto offset, an id with the start for a series, and the start as an instant" do
      occurrence = described_class::Occurrence.new(starts_at: at(2027, 11, 7, 1, 30) + 1.hour, ends_at: at(2027, 11, 7, 3), all_day: false)
      expect(occurrence.feed_row(7, { title: "Class", extendedProps: { a: 1 } }, repeating: true)).to eq(
        title: "Class", id: "7@#{Time.utc(2027, 11, 7, 6, 30).to_i}", start: "2027-11-07T01:30:00-05:00", end: "2027-11-07T03:00:00-05:00",
        allDay: false, extendedProps: { a: 1, occurrenceStart: "2027-11-07T06:30:00Z" }
      )
    end

    it "sends an all-day occurrence as Toronto dates and a single entry under its own key" do
      occurrence = described_class::Occurrence.new(starts_at: at(2027, 3, 14), ends_at: at(2027, 3, 15), all_day: true)
      expect(occurrence.feed_row("uid", { extendedProps: {} }, repeating: false))
        .to include(id: "uid", start: "2027-03-14", end: "2027-03-15", allDay: true)
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

    it "stops at the limit and says it was cut short" do
      result = starting(daily, at(2027, 5, 1), at(2027, 8, 1), limit: 3)
      expect([result.occurrences.size, result.truncated]).to eq([3, true])
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

    it "leaves a UNTIL with Z alone, whatever the time" do
      zulu = series("RRULE:FREQ=DAILY;UNTIL=20270304T110000Z", at(2027, 3, 1, 6), at(2027, 3, 1, 7))
      expect(times(starting(zulu, at(2027, 3, 1), at(2027, 4, 1))).size).to eq(4)
    end

    it "takes a VALUE=DATE exclusion as that day's midnight" do
      all_day = series("RRULE:FREQ=DAILY;COUNT=3\nEXDATE;VALUE=DATE:20270314", at(2027, 3, 13), at(2027, 3, 14))
      expect(times(starting(all_day, at(2027, 3, 1), at(2027, 4, 1)))).to eq(%w[2027-03-13T00:00:00-05:00 2027-03-15T00:00:00-04:00])
    end

    it "refuses a rule finer than daily when the series is built" do
      expect { series("RRULE:FREQ=HOURLY;COUNT=3", at(2027, 11, 7, 0), at(2027, 11, 7, 0, 30)) }
        .to raise_error(described_class::UnsupportedRule, /HOURLY/)
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

  describe "a window far from the series start" do
    # Repeat-library steps (one per period) taken while the block runs: a bound on the work, not on the time.
    def steps
      count = 0
      allow_any_instance_of(RRule::Frequency).to receive(:advance).and_wrap_original do |original, *args|
        count += 1
        original.call(*args)
      end
      yield
      count
    end

    # What walking from the original start gives: the gem asked directly, as the series did before it moved its start.
    def walked(rule, start, from, to)
      RRule::Rule.new(rule, dtstart: start, tzid: zone.tzinfo.name).between(from, to).map(&:to_i)
    end

    {
      "every third day at the skipped 02:30" => ["FREQ=DAILY;INTERVAL=3", [2026, 10, 26, 2, 30]],
      "every second week on Monday and Wednesday, started on a Wednesday" => ["FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE", [2026, 10, 28, 9]],
      "every second month on the 31st (a short month cannot hold the start)" => ["FREQ=MONTHLY;INTERVAL=2", [2026, 1, 31, 10]],
      "every third month on the last day" => ["FREQ=MONTHLY;INTERVAL=3;BYMONTHDAY=-1", [2026, 3, 14, 10]],
      "every second month on the last weekday" => ["FREQ=MONTHLY;INTERVAL=2;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", [2026, 10, 30, 9]],
      "every second year on 29 February" => ["FREQ=YEARLY;INTERVAL=2", [2028, 2, 29, 12]],
      "yearly on the second Sunday of March at 02:30" => ["FREQ=YEARLY;BYMONTH=3;BYDAY=SU;BYSETPOS=2", [2026, 3, 8, 2, 30]],
      "every second day at 01:30, in the repeated hour on 2028-11-05" => ["FREQ=DAILY;INTERVAL=2;UNTIL=20290101T050000Z", [2026, 11, 1, 1, 30]],
      "weekly with no interval" => ["FREQ=WEEKLY;BYDAY=SU", [2026, 11, 1, 1, 30]]
    }.each do |name, (rule, start_parts)|
      it "gives the occurrences of a walk from the original start: #{name}" do
        start = at(*start_parts)
        series = series("RRULE:#{rule}", start, start + 1.hour)
        [[at(2028, 10, 25), at(2028, 11, 15)], [at(2029, 3, 1), at(2029, 4, 15)], [at(2031, 1, 1), at(2031, 2, 1)]].each do |from, to|
          expect(starting(series, from, to).occurrences.map { |o| o.starts_at.to_i }).to eq(walked(rule, start, from, to)), "#{from.to_date}"
        end
      end
    end

    it "costs a few steps for a window in the year 9000, with an interval and without" do
      start = at(2026, 11, 2, 9)
      [["FREQ=WEEKLY;INTERVAL=2;BYDAY=MO", 3], ["FREQ=DAILY;INTERVAL=3", 7], ["FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=5", 2],
       ["FREQ=YEARLY;INTERVAL=2;BYMONTH=1;BYMONTHDAY=3", 1], ["FREQ=WEEKLY;BYDAY=MO", 4]].each do |rule, expected|
        result = nil
        taken = steps { result = starting(series("RRULE:#{rule}", start, start + 1.hour), at(9000, 1, 1), at(9000, 1, 20)) }
        expect(result.occurrences.size).to be >= 1, rule
        expect(result.occurrences.size).to be <= expected + 1, rule
        expect(taken).to be <= 12, rule
      end
    end

    it "walks a COUNT series from its start and stops at its end, however far the window is" do
      start = at(2026, 11, 2, 9)
      daily = series("RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=10", start, start + 1.hour)
      result = nil
      taken = steps { result = starting(daily, at(9000, 1, 1), at(9000, 1, 20)) }
      expect([result.occurrences, result.truncated]).to eq([[], false])
      expect(taken).to be <= 12
    end

    it "stops a rule that never matches within a hundred years of where it starts walking" do
      start = at(2026, 11, 2, 9)
      bound = (RecurringSeries::MAX_YEARS * 12) + 12
      ["FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;COUNT=3", "FREQ=MONTHLY;BYMONTH=2;BYMONTHDAY=30;COUNT=3",
       "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30", "FREQ=MONTHLY;BYMONTH=2;BYMONTHDAY=30"].each do |rule|
        [[at(2026, 12, 1), at(2027, 1, 1)], [at(9000, 1, 1), at(9000, 1, 20)]].each do |from, to|
          result = nil
          taken = steps { result = starting(series("RRULE:#{rule}", start, start + 1.hour), from, to) }
          expect(result.occurrences).to be_empty, rule
          expect(taken).to be <= bound, rule
        end
      end
    end

    it "reads a lower-case until like the gem's upper-case one" do
      lower = series("RRULE:FREQ=DAILY;until=20270303", at(2027, 3, 1, 22), at(2027, 3, 1, 23))
      expect(times(starting(lower, at(2027, 3, 1), at(2027, 4, 1))).size).to eq(3)
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
