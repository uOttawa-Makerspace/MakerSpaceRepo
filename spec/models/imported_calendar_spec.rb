# frozen_string_literal: true

require "rails_helper"

# An ICS feed read onto the same engine as the stored events. The fetch is stubbed at the boundary (IcsFetcher.get);
# the fixtures are the ones the browser rows are pinned against (spec/helpers/calendar_helper_ics_dst_spec.rb), and
# here the instants are the ones the files mean: both 2027 clock changes (forward 2027-03-14, back 2027-11-07).
RSpec.describe ImportedCalendar do
  include ActiveSupport::Testing::TimeHelpers

  let(:url) { "https://calendar.example.test/private/secret-token/feed.ics" }
  let(:toronto) { ActiveSupport::TimeZone["America/Toronto"] }
  let(:everything) { Time.utc(2027, 1, 1)..Time.utc(2028, 12, 31) }

  around { |example| travel_to(Time.utc(2027, 2, 1, 12)) { example.run } }

  def fixture(name) = Rails.root.join("spec/fixtures/files/ics/#{name}.ics").read

  def serve(body)
    allow(IcsFetcher).to receive(:get).with(url, timeout: 10).and_return(body)
  end

  def ics(*vevents)
    (["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//spec//EN"] + vevents.flatten + ["END:VCALENDAR"]).join("\r\n") + "\r\n"
  end

  def vevent(uid, *lines) = ["BEGIN:VEVENT", "UID:#{uid}", "DTSTAMP:20270101T000000Z", *lines, "END:VEVENT"]

  def entries_of(body, **options)
    serve(body)
    described_class.load(url, name: "Hours", color: "#123456", **options).entries
  end

  def entry(entries, uid, recurrence_id: nil) = entries.find { |e| e.uid == uid && e.recurrence_id&.to_i == recurrence_id&.to_i }

  # The Toronto wall times of a series' first occurrences.
  def starts(entry, count: 6)
    entry.series.occurrences_starting_in(everything, limit: count).occurrences
         .map { |occurrence| occurrence.starts_at.in_time_zone(toronto).strftime("%Y-%m-%dT%H:%M") }
  end

  def reported
    reports = []
    subscriber = Class.new { define_method(:report) { |error, handled:, severity:, context:, source:| reports << [error, context] } }.new
    Rails.error.subscribe(subscriber)
    yield
    reports
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  describe ".load" do
    it "gives the id (a digest of the link), colour, name and the entries with their display attributes" do
      body = ics(vevent("a", "DTSTART:20270215T150000Z", "DTEND:20270215T160000Z", "SUMMARY:Open", "DESCRIPTION:Walk in"))
      serve(body)
      calendar = described_class.load(url, name: "Hours", color: "#123456")

      expect(calendar).to have_attributes(id: Digest::MD5.hexdigest(url), color: "#123456", name: "Hours")
      expect(calendar).not_to be_failed
      expect(calendar).to be_fetched
      expect(calendar.entries.size).to eq(1)
      expect(calendar.entries.first).to have_attributes(
        uid: "a", key: "a", summary: "Open", description: "Walk in", all_day: false, series: nil,
        starts_at: Time.utc(2027, 2, 15, 15), ends_at: Time.utc(2027, 2, 15, 16)
      )
    end

    it "is failed and not fetched when the server gives no body" do
      serve(nil)
      calendar = described_class.load(url, name: "x", color: "#000")
      expect(calendar).to be_failed
      expect(calendar).not_to be_fetched
      expect(calendar.entries).to eq([])
    end

    it "is failed but fetched for a body that is not a calendar, or cannot be read, and not failed for an empty calendar" do
      serve("<html>sign in</html>")
      expect(described_class.load(url, name: "x", color: "#000")).to be_failed
      serve(ics(vevent("bad", "DTSTART:notadate")))
      unreadable = described_class.load(url, name: "x", color: "#000")
      expect(unreadable).to be_failed
      expect(unreadable).to be_fetched
      expect(unreadable.entries).to eq([])
      serve(ics)
      expect(described_class.load(url, name: "x", color: "#000")).not_to be_failed
    end

    it "logs only the host of a link, never its path" do
      serve(ics(vevent("bad", "DTSTART:notadate")))
      logged = []
      allow(Rails.logger).to receive(:error) { |message| logged << message }
      described_class.load(url, name: "x", color: "#000")
      expect(logged.join).to match(/ICS parse error for calendar\.example\.test: /)
      expect(logged.join).not_to match(/secret-token|feed\.ics/)
    end

    it "is failed and fetched when the link may not be fetched, without any request" do
      calendar = described_class.load("http://127.0.0.1/feed.ics", name: "x", color: "#000")
      expect(calendar).to be_failed
      expect(calendar).to be_fetched
      expect(a_request(:any, /./)).not_to have_been_made
    end
  end

  describe "a calendar in the Toronto zone" do
    let(:entries) { entries_of(fixture("toronto_tzid")) }

    it "keeps the wall time across both clock changes (a time that does not exist moves forward, a repeated one is listed once)" do
      expect(starts(entry(entries, "spring-0230@ics.test"))).to eq(%w[2027-03-07T02:30 2027-03-14T03:30 2027-03-21T02:30 2027-03-28T02:30 2027-04-04T02:30 2027-04-11T02:30])
      expect(starts(entry(entries, "fall-0130@ics.test"), count: 4)).to eq(%w[2027-10-31T01:30 2027-11-07T01:30 2027-11-14T01:30 2027-11-21T01:30])
    end

    it "has the length of the event" do
      series = entry(entries, "spring-0230@ics.test").series
      occurrence = series.occurrences_starting_in(everything, limit: 2).occurrences.last
      expect(occurrence.ends_at - occurrence.starts_at).to eq(3600)
    end
  end

  describe "a calendar in the Europe/Paris zone" do
    let(:entries) { entries_of(fixture("paris_tzid")) }

    # Paris changes its clocks on 2027-03-28 and 2027-10-31, Toronto on 2027-03-14 and 2027-11-07, so in between 09:00
    # in Paris is 04:00 in Toronto.
    it "repeats 09:00 in Paris, which is 04:00 Toronto time for two weeks after each Toronto change" do
      expect(entry(entries, "paris-spring@ics.test").starts_at.time_zone.name).to eq("Europe/Paris")
      expect(starts(entry(entries, "paris-spring@ics.test"), count: 4)).to eq(%w[2027-03-07T03:00 2027-03-14T04:00 2027-03-21T04:00 2027-03-28T03:00])
      expect(starts(entry(entries, "paris-fall@ics.test"), count: 4)).to eq(%w[2027-10-24T03:00 2027-10-31T04:00 2027-11-07T03:00 2027-11-14T03:00])
    end
  end

  describe "a calendar with a Windows zone name and its own VTIMEZONE" do
    let(:entries) { entries_of(fixture("windows_timezone")) }

    it "reads the zone as Eastern time and keeps the wall time across the clock changes" do
      spring = entry(entries, "windows-spring@ics.test")
      expect(spring.starts_at.time_zone.name).to eq("America/New_York")
      expect(starts(spring, count: 3)).to eq(%w[2027-03-07T02:30 2027-03-14T03:30 2027-03-21T02:30])
      expect(starts(entry(entries, "windows-fall@ics.test"), count: 3)).to eq(%w[2027-10-31T01:30 2027-11-07T01:30 2027-11-14T01:30])
    end
  end

  describe "a calendar with no zone (floating times)" do
    it "reads the times as Toronto wall time" do
      entries = entries_of(fixture("floating"))
      expect(entry(entries, "floating-spring@ics.test").starts_at).to eq(toronto.local(2027, 3, 7, 2, 30))
      expect(entry(entries, "floating-spring@ics.test").starts_at.time_zone).to eq(toronto)
      expect(starts(entry(entries, "floating-fall@ics.test"), count: 3)).to eq(%w[2027-10-31T01:30 2027-11-07T01:30 2027-11-14T01:30])
    end
  end

  describe "all-day series (VALUE=DATE)" do
    let(:entries) { entries_of(fixture("all_day")) }

    it "is all day, one Toronto day long, with whole days across the clock change" do
      spring = entry(entries, "allday-spring@ics.test")
      expect(spring).to have_attributes(all_day: true, starts_at: toronto.local(2027, 3, 7), ends_at: toronto.local(2027, 3, 8))
      change_day = spring.series.occurrences_starting_in(everything, limit: 2).occurrences.last
      expect(change_day.starts_at).to eq(toronto.local(2027, 3, 14))
      expect(change_day.ends_at).to eq(toronto.local(2027, 3, 15))
      expect(change_day.all_day).to be(true)
    end

    it "leaves out a date exclusion (the Toronto midnight of that day)" do
      fall = entry(entries, "allday-fall@ics.test")
      expect(starts(fall, count: 3)).to eq(%w[2027-10-31T00:00 2027-11-14T00:00 2027-11-21T00:00])
    end

    it "gives an all-day event with no end a one-day length" do
      entries = entries_of(ics(vevent("day", "DTSTART;VALUE=DATE:20270315", "SUMMARY:Closed", "RRULE:FREQ=DAILY;COUNT=2")))
      series = entries.first.series
      expect(entries.first.ends_at).to be_nil
      expect(series.occurrences_starting_in(everything, limit: 1).occurrences.first.all_day).to be(true)
    end
  end

  describe "an exclusion in the hour the clocks repeat" do
    let(:entries) { entries_of(fixture("exdate_repeated_hour")) }

    # The 01:30 of the change day is listed once, at its first instant (05:30Z). An exclusion of that instant, or of the
    # zoned wall time (which is the first one), removes the day; one of the second instant (06:30Z) is a different
    # instant and removes nothing.
    it "removes the day for the first 01:30 and the zoned wall time, and keeps it for the second 01:30" do
      expect(starts(entry(entries, "exdate-first@ics.test"), count: 3)).to eq(%w[2027-10-31T01:30 2027-11-14T01:30 2027-11-21T01:30])
      expect(starts(entry(entries, "exdate-local@ics.test"), count: 3)).to eq(%w[2027-10-31T01:30 2027-11-14T01:30 2027-11-21T01:30])
      expect(starts(entry(entries, "exdate-utc@ics.test"), count: 3)).to eq(%w[2027-10-31T01:30 2027-11-07T01:30 2027-11-14T01:30])
    end
  end

  describe "a modified instance (RECURRENCE-ID)" do
    let(:entries) { entries_of(fixture("recurrence_id_moved")) }

    it "excludes the original instant from the series and lists the moved instance once, as an event of its own" do
      expect(starts(entry(entries, "moved@ics.test"), count: 4)).to eq(%w[2027-03-07T10:00 2027-03-21T10:00 2027-03-28T10:00 2027-04-04T10:00])
      moved = entry(entries, "moved@ics.test", recurrence_id: toronto.local(2027, 3, 14, 10))
      expect(moved).to have_attributes(summary: "Sunday class (moved to Monday)", starts_at: toronto.local(2027, 3, 15, 14), series: nil,
                                       key: "moved@ics.test_1805032800")
      expect(entries.size).to eq(2)
    end
  end

  describe "a cancelled instance and a cancelled series (STATUS:CANCELLED)" do
    let(:entries) { entries_of(fixture("recurrence_id_cancelled")) }

    it "leaves the cancelled instance out of the series, draws nothing for it, and drops the cancelled series" do
      expect(entries.map(&:uid)).to eq(["cancelled@ics.test"])
      expect(starts(entries.first, count: 4)).to eq(%w[2027-03-07T10:00 2027-03-21T10:00 2027-03-28T10:00 2027-04-04T10:00])
    end
  end

  describe "a series with an end (UNTIL)" do
    let(:entries) { entries_of(fixture("until")) }

    it "keeps the last day of a date UNTIL" do
      expect(starts(entry(entries, "until-date@ics.test"))).to eq(%w[2027-03-07T00:00 2027-03-14T00:00 2027-03-21T00:00 2027-03-28T00:00])
    end

    it "keeps the occurrence a UTC UNTIL names" do
      expect(starts(entry(entries, "until-utc@ics.test"))).to eq(%w[2027-03-07T10:00 2027-03-14T10:00 2027-03-21T10:00])
      expect(starts(entry(entries, "until-utc-fall@ics.test"))).to eq(%w[2027-10-31T01:30 2027-11-07T01:30])
    end

    it "keeps the last day of a date UNTIL for a timed series" do
      body = ics(vevent("timed", "DTSTART;TZID=America/Toronto:20270307T100000", "DTEND;TZID=America/Toronto:20270307T110000",
                        "RRULE:FREQ=WEEKLY;BYDAY=SU;UNTIL=20270321", "SUMMARY:Timed"))
      expect(starts(entries_of(body).first)).to eq(%w[2027-03-07T10:00 2027-03-14T10:00 2027-03-21T10:00])
    end
  end

  describe "a series with a COUNT" do
    it "counts the repeated hour once" do
      entries = entries_of(fixture("count"))
      expect(starts(entry(entries, "count-fall@ics.test"))).to eq(%w[2027-10-31T01:30 2027-11-07T01:30 2027-11-14T01:30])
      expect(starts(entry(entries, "count-spring@ics.test"))).to eq(%w[2027-03-07T02:30 2027-03-14T03:30 2027-03-21T02:30])
    end
  end

  describe "a rule with BYSETPOS or BYWEEKNO" do
    let(:entries) { entries_of(fixture("bysetpos")) }

    it "applies BYSETPOS (the last weekday of the month, the second Sunday, the first Sunday)" do
      expect(starts(entry(entries, "last-weekday@ics.test"), count: 4)).to eq(%w[2027-02-26T09:00 2027-03-31T09:00 2027-04-30T09:00 2027-05-31T09:00])
      expect(starts(entry(entries, "second-sunday-march@ics.test"), count: 4)).to eq(%w[2027-02-14T02:30 2027-03-14T03:30 2027-04-11T02:30 2027-05-09T02:30])
      expect(starts(entry(entries, "first-sunday-november@ics.test"), count: 3)).to eq(%w[2027-10-03T01:30 2027-11-07T01:30 2027-12-05T01:30])
    end

    it "applies BYWEEKNO" do
      body = ics(vevent("week", "DTSTART;TZID=America/Toronto:20270104T090000", "DTEND;TZID=America/Toronto:20270104T100000",
                        "RRULE:FREQ=YEARLY;BYWEEKNO=3;BYDAY=MO;COUNT=2", "SUMMARY:Week 3"))
      expect(starts(entries_of(body).first, count: 3)).to eq(%w[2027-01-18T09:00 2028-01-17T09:00])
    end
  end

  describe "what is left out" do
    it "drops a single event that ended more than two months ago and keeps a series that has not ended" do
      body = ics(
        vevent("old", "DTSTART:20261001T150000Z", "DTEND:20261001T160000Z", "SUMMARY:Old"),
        vevent("rec", "DTSTART:20261001T150000Z", "DTEND:20261001T160000Z", "SUMMARY:Rec", "RRULE:FREQ=DAILY")
      )
      expect(entries_of(body).map(&:uid)).to eq(["rec"])
    end

    it "drops a series by its UNTIL or COUNT only when its last occurrence was more than two months ago" do
      stamp = "DTSTART:20261001T150000Z"
      body = ics(
        vevent("until-old", stamp, "SUMMARY:A", "RRULE:FREQ=DAILY;UNTIL=20261010T150000Z"),
        vevent("count-old", stamp, "SUMMARY:B", "RRULE:FREQ=WEEKLY;COUNT=3"),
        vevent("until-recent", stamp, "SUMMARY:C", "RRULE:FREQ=DAILY;UNTIL=20270120T150000Z"),
        vevent("count-straddles", stamp, "SUMMARY:D", "RRULE:FREQ=WEEKLY;COUNT=40"),
        vevent("count-huge", stamp, "SUMMARY:E", "RRULE:FREQ=YEARLY;COUNT=5000")
      )
      expect(entries_of(body).map(&:uid)).to eq(%w[until-recent count-straddles count-huge])
    end

    it "lists a recent modified instance of a series that ended, and one whose master is not in the feed" do
      body = ics(
        vevent("rec", "DTSTART:20261001T150000Z", "DTEND:20261001T160000Z", "SUMMARY:Weekly", "RRULE:FREQ=WEEKLY;COUNT=3"),
        vevent("rec", "RECURRENCE-ID:20261008T150000Z", "DTSTART:20270108T170000Z", "DTEND:20270108T180000Z", "SUMMARY:Moved"),
        vevent("orphan", "RECURRENCE-ID;VALUE=DATE:20270112", "DTSTART;VALUE=DATE:20270112", "DTEND;VALUE=DATE:20270113", "SUMMARY:Alone"),
        vevent("ancient", "RECURRENCE-ID:20260101T150000Z", "DTSTART:20260101T170000Z", "SUMMARY:Ancient")
      )
      expect(entries_of(body).map(&:summary)).to eq(%w[Moved Alone])
    end

    it "keeps single events and modified instances without an end, judging their age by the start" do
      body = ics(
        vevent("day", "DTSTART;VALUE=DATE:20270112", "SUMMARY:All day"),
        vevent("old", "DTSTART:20261001T150000Z", "SUMMARY:Old")
      )
      expect(entries_of(body).map(&:summary)).to eq(["All day"])
    end

    it "reports an event with no start and leaves it out, and still lists the others" do
      body = ics(
        vevent("fine", "DTSTART:20270215T150000Z", "DTEND:20270215T160000Z", "SUMMARY:Fine"),
        vevent("nostart", "DTEND:20270215T160000Z", "SUMMARY:Broken", "RRULE:FREQ=DAILY;COUNT=2"),
        vevent("rec", "DTSTART:20270215T150000Z", "DTEND:20270215T160000Z", "SUMMARY:Weekly", "RRULE:FREQ=WEEKLY;COUNT=4"),
        vevent("rec", "RECURRENCE-ID:20270222T150000Z", "DTEND:20270222T180000Z", "SUMMARY:No start")
      )
      entries = nil
      reports = reported { entries = entries_of(body) }
      expect(entries.map(&:uid)).to eq(%w[fine rec])
      expect(reports.map { |error, context| [error.message, context[:event_uid], context[:calendar]] })
        .to eq([["ICS event has no usable start", "nostart", Digest::MD5.hexdigest(url)], ["ICS event has no usable start", "rec", Digest::MD5.hexdigest(url)]])
    end

    # One example per class of rule that fails the checks stored rules pass: it is reported once (event uid and calendar
    # digest, never the link or the rule) and the event is shown once, at its own start, as a single event.
    {
      "a value out of range" => "FREQ=DAILY;BYYEARDAY=400",
      "a month out of range" => "FREQ=YEARLY;BYMONTH=13",
      "a day of the month of 0" => "FREQ=MONTHLY;BYMONTHDAY=0",
      "a day of the month of 32" => "FREQ=MONTHLY;BYMONTHDAY=32",
      "a week number of 0" => "FREQ=YEARLY;BYWEEKNO=0",
      "a week number of 54" => "FREQ=YEARLY;BYWEEKNO=54",
      "a set position of 0" => "FREQ=MONTHLY;BYDAY=MO;BYSETPOS=0",
      "a set position of 367" => "FREQ=MONTHLY;BYDAY=MO;BYSETPOS=367",
      "a weekday ordinal of 0" => "FREQ=MONTHLY;BYDAY=0MO",
      "a weekday ordinal of 54" => "FREQ=MONTHLY;BYDAY=54MO",
      "a monthly weekday ordinal of 53" => "FREQ=MONTHLY;BYDAY=53MO",
      "a date that never comes" => "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30",
      "an interval of 0" => "FREQ=WEEKLY;INTERVAL=0",
      "a rule finer than daily" => "FREQ=HOURLY"
    }.each do |label, rule|
      it "reports #{label} and shows the event once, at its own start, with the rest of the feed intact" do
        body = ics(
          vevent("odd", "DTSTART:20270215T150000Z", "DTEND:20270215T160000Z", "SUMMARY:Odd", "RRULE:#{rule}"),
          vevent("fine", "DTSTART:20270215T150000Z", "SUMMARY:Fine", "RRULE:FREQ=WEEKLY")
        )
        calendar = nil
        reports = reported { serve(body); calendar = described_class.load(url, name: "x", color: "#000") }
        expect(calendar).not_to be_failed
        expect(calendar.entries.map(&:uid)).to eq(%w[odd fine])
        expect(calendar.entries.first).to have_attributes(series: nil, starts_at: Time.utc(2027, 2, 15, 15), ends_at: Time.utc(2027, 2, 15, 16))
        expect(calendar.entries.last.series).not_to be_nil
        expect(reports.size).to eq(1)
        expect(reports.first.last).to include(event_uid: "odd", calendar: Digest::MD5.hexdigest(url))
        expect(reports.first.first.message).not_to include(rule, "secret-token")
      end
    end

    it "reports an event that raises while it is read, leaves out only that event, and never empties the feed" do
      body = ics(
        vevent("boom", "DTSTART:20270215T150000Z", "SUMMARY:Boom", "RRULE:FREQ=WEEKLY"),
        vevent("fine", "DTSTART:20270215T150000Z", "SUMMARY:Fine", "RRULE:FREQ=WEEKLY")
      )
      original = RecurringSeries.method(:from_ics)
      allow(RecurringSeries).to receive(:from_ics) { |master, *rest, **options| master.uid.to_s == "boom" ? raise(TypeError, "bug") : original.call(master, *rest, **options) }
      calendar = nil
      reports = reported { serve(body); calendar = described_class.load(url, name: "x", color: "#000") }
      expect(calendar).not_to be_failed
      expect(calendar.entries.map(&:uid)).to eq(["fine"])
      expect(reports.map { |error, context| [error.class, context[:event_uid]] }).to eq([[TypeError, "boom"]])
    end

    it "keeps the first events of a feed with too many, and reports it once" do
      stub_const("ImportedCalendar::MAX_EVENTS", 2)
      body = ics(3.times.map { |i| vevent("e#{i}", "DTSTART:20270215T150000Z", "SUMMARY:E#{i}") })
      entries = nil
      reports = reported { entries = entries_of(body) }
      expect(entries.map(&:uid)).to eq(%w[e0 e1])
      expect(reports.map { |error, _| error.message }).to eq(["ICS feed has more than 2 events; the first 2 are kept"])
    end

    it "reads a zone name that is neither IANA nor Windows as Toronto and reports it once per feed, not per event" do
      body = ics(
        vevent("a", "DTSTART;TZID=Nowhere/Land:20270215T090000", "SUMMARY:A"),
        vevent("b", "DTSTART;TZID=Nowhere/Land:20270216T090000", "DTEND;TZID=Nowhere/Land:20270216T100000", "SUMMARY:B"),
        vevent("c", "DTSTART;TZID=Elsewhere:20270217T090000", "SUMMARY:C")
      )
      entries = nil
      reports = reported { entries = entries_of(body) }
      expect(entries.size).to eq(3)
      expect(reports.map { |error, _| error.message }).to contain_exactly("unknown time zone Nowhere/Land; read as Toronto time",
                                                                          "unknown time zone Elsewhere; read as Toronto time")
    end
  end

  describe ".time_of" do
    def value(line) = Icalendar::Calendar.parse(ics(vevent("a", line))).first.events.first.dtstart

    it "reads a date as midnight in the given zone (Toronto by default)" do
      expect(described_class.time_of(value("DTSTART;VALUE=DATE:20270315"))).to eq(toronto.local(2027, 3, 15))
      paris = ActiveSupport::TimeZone["Europe/Paris"]
      expect(described_class.time_of(value("DTSTART;VALUE=DATE:20270315"), paris)).to eq(paris.local(2027, 3, 15))
    end

    it "keeps the instant and zone of a UTC or zoned time and reads a floating one as Toronto wall time" do
      expect(described_class.time_of(value("DTSTART:20270315T150000Z"))).to eq(Time.utc(2027, 3, 15, 15))
      expect(described_class.time_of(value("DTSTART:20270315T150000Z")).time_zone.name).to eq("UTC")
      expect(described_class.time_of(value("DTSTART:20270315T090000"))).to eq(toronto.local(2027, 3, 15, 9))
      expect(described_class.time_of(value("DTSTART;TZID=Europe/Paris:20270315T090000"))).to eq(Time.utc(2027, 3, 15, 8))
    end

    it "reads a zone name it cannot resolve at its own offset instant, in Toronto" do
      body = ics("BEGIN:VTIMEZONE", "TZID:Custom Zone", "BEGIN:STANDARD", "DTSTART:16010101T000000", "TZOFFSETFROM:+0200", "TZOFFSETTO:+0200", "END:STANDARD",
                 "END:VTIMEZONE", vevent("a", "DTSTART;TZID=Custom Zone:20270315T090000"))
      time = described_class.time_of(Icalendar::Calendar.parse(body).first.events.first.dtstart)
      expect(time).to eq(Time.utc(2027, 3, 15, 7))
      expect(time.time_zone).to eq(toronto)
    end

    it "is nil for no value" do
      expect(described_class.time_of(nil)).to be_nil
    end
  end

  describe "the cached body" do
    let(:store) { ActiveSupport::Cache::MemoryStore.new }
    let(:body) { ics(vevent("a", "DTSTART:20270215T150000Z", "DTEND:20270215T160000Z", "SUMMARY:Private class")) }

    before do
      allow(Rails).to receive(:cache).and_return(store)
      allow(IcsFetcher).to receive(:get).with(url, timeout: 10).and_return(body)
    end

    def load_calendar(**options) = described_class.load(url, name: "x", color: "#000", **options)

    it "reads the link once for a repeated load within ten minutes, then again after" do
      2.times { expect(load_calendar.entries.map(&:uid)).to eq(["a"]) }
      expect(IcsFetcher).to have_received(:get).once
      travel(11.minutes)
      load_calendar
      expect(IcsFetcher).to have_received(:get).twice
    end

    it "reads the link again, and keeps the new copy, when asked for a fresh load" do
      load_calendar
      newer = body.sub("Private class", "Changed class")
      allow(IcsFetcher).to receive(:get).with(url, timeout: 10).and_return(newer)
      expect(load_calendar.entries.first.summary).to eq("Private class")
      expect(load_calendar(fresh: true).entries.first.summary).to eq("Changed class")
      expect(load_calendar.entries.first.summary).to eq("Changed class")
      expect(IcsFetcher).to have_received(:get).twice
    end

    it "does not keep a failure: no body, or an error from the fetch" do
      allow(IcsFetcher).to receive(:get).with(url, timeout: 10).and_return(nil, body)
      expect(load_calendar).to be_failed
      expect(load_calendar).not_to be_failed
      expect(IcsFetcher).to have_received(:get).twice

      allow(IcsFetcher).to receive(:get).with(url, timeout: 10).and_raise(IcsFetcher::Refused, "host is not public")
      store.clear
      expect(load_calendar).to be_failed
      expect(store.instance_variable_get(:@data)).to be_empty
    end

    it "keeps the body and the entries encrypted, under keys that do not hold the link" do
      load_calendar
      data = store.instance_variable_get(:@data)
      expect(data.keys.size).to eq(2)
      expect(data.keys.join).not_to include("secret-token")
      expect(data.keys).to include("ics-body/#{Digest::SHA256.hexdigest(url)}")

      raw = store.read(["ics-body", Digest::SHA256.hexdigest(url)])
      expect(raw).to be_a(String)
      expect(raw).not_to include("Private class", "BEGIN:VCALENDAR")
      expect(described_class.cipher.decrypt_and_verify(raw)).to eq(body)
      entries_key = data.keys.find { |key| key.start_with?("ics-entries/") }
      expect(data[entries_key].value.to_s).not_to include("Private class")
    end

    it "does not parse or expand a feed it already has the entries of, and the entries equal the first read" do
      rec = ics(vevent("rec", "DTSTART:20270215T150000Z", "DTEND:20270215T160000Z", "SUMMARY:Weekly", "RRULE:FREQ=WEEKLY;COUNT=5", "EXDATE:20270222T150000Z"))
      allow(IcsFetcher).to receive(:get).with(url, timeout: 10).and_return(rec)
      first = load_calendar.entries
      expect(Icalendar::Calendar).not_to receive(:parse)
      expect(RecurringSeries).not_to receive(:from_ics)
      again = load_calendar.entries
      expect(again.map { |e| [e.uid, e.starts_at, e.series.rule] }).to eq(first.map { |e| [e.uid, e.starts_at, e.series.rule] })
      expect(again.first.series.occurrences_starting_in(everything, limit: 10).occurrences.size).to eq(4)
    end

    it "parses again when the feed changes, and when a fresh load is asked for" do
      load_calendar
      allow(IcsFetcher).to receive(:get).with(url, timeout: 10).and_return(body.sub("Private class", "Changed class"))
      expect(load_calendar(fresh: true).entries.first.summary).to eq("Changed class")
    end

    it "does not keep an empty body" do
      allow(IcsFetcher).to receive(:get).with(url, timeout: 10).and_return("")
      expect(load_calendar).to be_failed
      expect(store.instance_variable_get(:@data)).to be_empty
    end

    it "reports a copy it cannot decrypt (without the link), then reads the feed again" do
      load_calendar
      store.write(["ics-body", Digest::SHA256.hexdigest(url)], "not a sealed copy")
      calendar = nil
      logged = []
      allow(Rails.logger).to receive(:error) { |message| logged << message }
      reports = reported { calendar = load_calendar }
      expect(calendar).not_to be_failed
      expect(calendar.entries.map(&:uid)).to eq(["a"])
      expect(reports.map { |error, _| error.class }).to eq([ActiveSupport::MessageEncryptor::InvalidMessage])
      expect(logged.join).to match(/ICS cache copy unreadable: ActiveSupport::MessageEncryptor::InvalidMessage/)
      expect(logged.join).not_to include("secret-token")
    end
  end
end
