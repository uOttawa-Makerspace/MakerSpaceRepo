require 'rails_helper'

RSpec.describe CalendarHelper, type: :helper do
  include ActiveSupport::Testing::TimeHelpers

  describe "#parse_ics_calendar" do
    let(:path) do
      Rails.root.join("spec/support/assets/MakerRepo Test Calendar_d1ee6078f7d085e62d99150ed598526f1ead2068937d30d9b3a93b48e4b17dc0@group.calendar.google.com.ics")
    end

    it "returns no calendars for a blank url" do
      expect(parse_ics_calendar(nil)).to eq([])
      expect(parse_ics_calendar("")).to eq([])
    end

    it "pulls the event out of the ICS file, grouped under the md5 of the source" do
      # the fixture's only event ended 2025-11-17; events older than two months are dropped
      travel_to(Time.utc(2025, 11, 20, 12, 0)) do
        result = parse_ics_calendar(path, name: "Maker", color: "#123456")

        expect(result.size).to eq(1)
        group = result.first
        expect(group[:id]).to eq(Digest::MD5.hexdigest(path.to_s))
        expect(group[:color]).to eq("#123456")
        expect(group[:events].size).to eq(1)

        event = group[:events].first
        expect(event).to include(
          id: "2bgvhuelmj9hk3e5dvrsfrl9ba@google.com",
          groupId: group[:id],
          title: "Apples",
          allDay: true,
          display: "auto"
        )
        expect(event[:extendedProps]).to eq(name: "Maker", description: nil)
        expect(event).not_to have_key(:rrule)
        # all-day dates are calendar dates in Toronto
        expect(event[:start]).to eq("2025-11-16T00:00:00")
        expect(event[:end]).to eq("2025-11-17T00:00:00")
      end
    end

    it "logs only the file name when a feed file cannot be read" do
      Dir.mktmpdir("private-folder") do |dir|
        file = Pathname.new(dir).join("feed.ics")
        file.write("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:bad\r\nDTSTART:notadate\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
        logged = []
        allow(Rails.logger).to receive(:error) { |message| logged << message }

        expect(ics_feed(file, name: "x")).to be_failed
        expect(logged.join).to match(/ICS parse error for feed\.ics/)
        expect(logged.join).not_to include("private-folder")
      end
    end

    it "drops events that ended more than two months ago" do
      travel_to(Time.utc(2026, 3, 1, 12, 0)) do
        expect(parse_ics_calendar(path).first[:events]).to eq([])
      end
    end

    it "reads no events from a URL that may not be fetched, without any request" do
      result = parse_ics_calendar("http://127.0.0.1/feed.ics")
      expect(result.first[:events]).to eq([])
      expect(a_request(:any, /./)).not_to have_been_made
    end

    it "generates a colour from the source when none is given" do
      travel_to(Time.utc(2025, 11, 20, 12, 0)) do
        color = parse_ics_calendar(path).first[:color]
        expect(color).to eq(generate_color_from_id(path.to_s))
        expect(color).to match(/\Argba\(\d+, \d+, \d+, 1\.0\)\z/)
      end
    end
  end

  describe "#parse_ics_calendar from a URL" do
    let(:url) { "https://calendar.example/feed.ics" }

    def ics(*vevents)
      (["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//spec//EN"] + vevents.flatten + ["END:VCALENDAR"]).join("\r\n") + "\r\n"
    end

    def vevent(uid, lines)
      ["BEGIN:VEVENT", "UID:#{uid}", "DTSTAMP:20270101T000000Z", *lines, "END:VEVENT"]
    end

    around { |example| travel_to(Time.utc(2027, 1, 10, 12, 0)) { example.run } }

    # The [message, context] of every problem reported (Rails.error) while the block runs.
    def reported_ics_problems
      reports = []
      subscriber = Class.new { define_method(:report) { |error, handled:, severity:, context:, source:| reports << [error.message, context] } }.new
      Rails.error.subscribe(subscriber)
      begin
        yield
      ensure
        Rails.error.unsubscribe(subscriber)
      end
      reports
    end

    it "returns no calendar at all (not an empty one) when the fetch gives no body" do
      stub_request(:get, url).to_return(status: 404, body: "")
      expect(parse_ics_calendar(url)).to eq([])
    end

    it "logs and returns no events for a body with a value that is not a date" do
      stub_request(:get, url).to_return(status: 200, body: ics(vevent("bad", ["DTSTART:notadate", "SUMMARY:Bad"])))
      allow(Rails.logger).to receive(:error)
      expect(parse_ics_calendar(url).first[:events]).to eq([])
      expect(Rails.logger).to have_received(:error).with(/ICS parse error for calendar\.example\b/)
    end

    it "logs only the host of a link, never its path or query" do
      secret = "https://calendar.example/private/secret-token/feed.ics?key=abc"
      stub_request(:get, secret).to_return(status: 200, body: ics(vevent("bad", ["DTSTART:notadate", "SUMMARY:Bad"])))
      logged = []
      allow(Rails.logger).to receive(:error) { |message| logged << message }
      parse_ics_calendar(secret)
      expect(logged).not_to be_empty
      expect(logged.join).not_to match(/secret-token|key=abc|feed\.ics/)
    end

    it "reports a feed as failed when it cannot be fetched, is not a calendar, or cannot be read, but not when it is an empty calendar" do
      stub_request(:get, url).to_return(status: 404, body: "")
      expect(ics_feed(url, name: "x")).to be_failed
      stub_request(:get, url).to_return(status: 200, body: "<html>sign in</html>")
      expect(ics_feed(url, name: "x")).to be_failed
      stub_request(:get, url).to_return(status: 200, body: ics(vevent("bad", ["DTSTART:notadate"])))
      expect(ics_feed(url, name: "x")).to be_failed
      stub_request(:get, url).to_return(status: 200, body: ics)
      expect(ics_feed(url, name: "x")).not_to be_failed
      expect(ics_feed(nil, name: "x")).not_to be_failed
    end

    it "uses the given name, and groups the calendar under the md5 of its URL" do
      stub_request(:get, url).to_return(status: 200, body: ics(vevent("a", ["DTSTART:20270115T150000Z", "DTEND:20270115T160000Z", "SUMMARY:Open", "DESCRIPTION:Walk in"])))
      group = parse_ics_calendar(url, name: "Hours", color: "#abcdef").first
      expect(group).to include(id: Digest::MD5.hexdigest(url), color: "#abcdef")
      expect(group[:events].first).to include(title: "Open", allDay: false, start: "2027-01-15T10:00:00", end: "2027-01-15T11:00:00")
      expect(group[:events].first[:extendedProps]).to eq(name: "Hours", description: "Walk in")
    end

    it "drops a single event that ended more than two months ago and keeps a series that has not ended" do
      body = ics(
        vevent("old", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:Old"]),
        vevent("rec", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:Rec", "RRULE:FREQ=DAILY"])
      )
      stub_request(:get, url).to_return(status: 200, body: body)
      expect(parse_ics_calendar(url).first[:events].map { |e| e[:id] }).to eq(["rec"])
    end

    it "drops a series whose last day or last counted occurrence was more than two months ago" do
      body = ics(
        vevent("until-old", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:A", "RRULE:FREQ=DAILY;UNTIL=20260810T150000Z"]),
        vevent("count-old", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:B", "RRULE:FREQ=WEEKLY;COUNT=3"]),
        vevent("until-recent", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:C", "RRULE:FREQ=DAILY;UNTIL=20261220T150000Z"]),
        vevent("count-recent", ["DTSTART:20261201T150000Z", "DTEND:20261201T160000Z", "SUMMARY:D", "RRULE:FREQ=WEEKLY;COUNT=10"]),
        vevent("count-straddles", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:E", "RRULE:FREQ=WEEKLY;COUNT=40"]),
        vevent("count-huge", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:F", "RRULE:FREQ=YEARLY;COUNT=5000"]),
        vevent("unreadable", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:G", "RRULE:FREQ=WEEKLY;BYWEEKNO=3;COUNT=2"])
      )
      stub_request(:get, url).to_return(status: 200, body: body)
      expect(parse_ics_calendar(url).first[:events].map { |e| e[:id] })
        .to eq(%w[until-recent count-recent count-straddles count-huge unreadable])
    end

    it "still lists a modified instance of a series that has ended when the instance is recent" do
      body = ics(
        vevent("rec", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:Weekly", "RRULE:FREQ=WEEKLY;COUNT=3"]),
        vevent("rec", ["RECURRENCE-ID:20260808T150000Z", "DTSTART:20270108T170000Z", "DTEND:20270108T180000Z", "SUMMARY:Moved"])
      )
      stub_request(:get, url).to_return(status: 200, body: body)
      expect(parse_ics_calendar(url).first[:events].map { |e| e[:title] }).to eq(["Moved"])
    end

    it "turns a recurring event into an rrule string with DTSTART, the rule, the exdates and a duration in ms" do
      body = ics(vevent("rec", [
        "DTSTART:20270105T150000Z", "DTEND:20270105T163000Z", "SUMMARY:Weekly",
        "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;UNTIL=20271231T000000Z",
        "EXDATE:20270119T150000Z"
      ]))
      stub_request(:get, url).to_return(status: 200, body: body)
      event = parse_ics_calendar(url).first[:events].first
      lines = event[:rrule].split("\n")
      expect(lines.first).to eq("DTSTART:20270105T100000")
      expect(lines[1]).to start_with("RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;UNTIL=20271230T190000")
      expect(lines.last).to eq("EXDATE:20270119T100000")
      expect(event[:duration]).to eq(90 * 60 * 1000)
    end

    it "excludes the recurrence-id dates of modified instances and lists each modified instance as its own event" do
      body = ics(
        vevent("rec", ["DTSTART:20270105T150000Z", "DTEND:20270105T160000Z", "SUMMARY:Weekly", "RRULE:FREQ=WEEKLY;BYDAY=TU;COUNT=4"]),
        vevent("rec", ["RECURRENCE-ID:20270112T150000Z", "DTSTART:20270112T170000Z", "DTEND:20270112T180000Z", "SUMMARY:Moved"]),
        vevent("rec", ["RECURRENCE-ID:20260101T150000Z", "DTSTART:20260101T170000Z", "DTEND:20260101T180000Z", "SUMMARY:Ancient"])
      )
      stub_request(:get, url).to_return(status: 200, body: body)
      events = parse_ics_calendar(url).first[:events]
      expect(events.size).to eq(2)
      main, moved = events
      expect(main[:rrule]).to include("EXDATE:20270112T100000")
      expect(moved).to include(title: "Moved", start: "2027-01-12T12:00:00", allDay: false)
      expect(moved[:id]).to eq("rec_#{Time.utc(2027, 1, 12, 15).to_i}")
    end

    it "leaves out an event that has no start, reports it, and still lists the other events" do
      body = ics(
        vevent("fine", ["DTSTART:20270115T150000Z", "DTEND:20270115T160000Z", "SUMMARY:Fine"]),
        vevent("nostart", ["DTEND:20270115T160000Z", "SUMMARY:Broken", "RRULE:FREQ=DAILY;COUNT=2"]),
        vevent("nostart-single", ["DTEND:20270115T160000Z", "SUMMARY:Broken too"])
      )
      stub_request(:get, url).to_return(status: 200, body: body)
      events = nil
      reports = reported_ics_problems { events = parse_ics_calendar(url).first[:events] }
      expect(events.map { |e| e[:id] }).to eq(["fine"])
      expect(reports.map(&:first)).to all(eq("ICS event has no usable start"))
      expect(reports.map { |_, context| context[:event_uid] }).to eq(%w[nostart nostart-single])
      expect(reports.first.last[:calendar]).to eq(Digest::MD5.hexdigest(url))
    end

    it "gives a recurring event without an end no end time and no duration" do
      body = ics(vevent("noend", ["DTSTART:20270115T150000Z", "SUMMARY:Open ended", "RRULE:FREQ=DAILY;COUNT=2"]))
      stub_request(:get, url).to_return(status: 200, body: body)
      event = parse_ics_calendar(url).first[:events].first
      expect(event[:end]).to be_nil
      expect(event[:start]).to eq("2027-01-15T10:00:00")
      expect(event).not_to have_key(:duration)
      expect(event[:rrule]).to start_with("DTSTART:20270115T100000")
    end

    it "keeps single events and modified instances without an end, judging their age by the start" do
      body = ics(
        vevent("day", ["DTSTART;VALUE=DATE:20270112", "SUMMARY:All day"]),
        vevent("old", ["DTSTART:20260801T150000Z", "SUMMARY:Old"]),
        vevent("rec", ["DTSTART:20270105T150000Z", "DTEND:20270105T160000Z", "SUMMARY:Weekly", "RRULE:FREQ=WEEKLY;COUNT=4"]),
        vevent("rec", ["RECURRENCE-ID:20270112T150000Z", "DTSTART:20270112T170000Z", "SUMMARY:Moved"]),
        vevent("rec", ["RECURRENCE-ID:20260101T150000Z", "DTSTART:20260101T170000Z", "SUMMARY:Ancient"])
      )
      stub_request(:get, url).to_return(status: 200, body: body)
      events = parse_ics_calendar(url).first[:events]
      expect(events.map { |e| e[:title] }).to match_array(["All day", "Weekly", "Moved"])
      expect(events.find { |e| e[:title] == "All day" }).to include(allDay: true, start: "2027-01-12T00:00:00", end: nil)
    end

    it "lists a modified instance whose master event is not in the feed" do
      body = ics(vevent("orphan", ["RECURRENCE-ID;VALUE=DATE:20270112", "DTSTART;VALUE=DATE:20270112", "DTEND;VALUE=DATE:20270113", "SUMMARY:Alone"]))
      stub_request(:get, url).to_return(status: 200, body: body)
      events = parse_ics_calendar(url).first[:events]
      expect(events.map { |e| [e[:title], e[:allDay]] }).to eq([["Alone", true]])
    end

    it "leaves out a modified instance that has no start of its own, and reports it" do
      body = ics(
        vevent("rec", ["DTSTART:20270105T150000Z", "DTEND:20270105T160000Z", "SUMMARY:Weekly", "RRULE:FREQ=WEEKLY;COUNT=4"]),
        vevent("rec", ["RECURRENCE-ID:20270112T150000Z", "DTEND:20270112T180000Z", "SUMMARY:No start"])
      )
      stub_request(:get, url).to_return(status: 200, body: body)
      events = nil
      reports = reported_ics_problems { events = parse_ics_calendar(url).first[:events] }
      expect(events.map { |e| e[:title] }).to eq(["Weekly"])
      expect(reports.map { |message, context| [message, context[:event_uid]] }).to eq([["ICS event has no usable start", "rec"]])
    end

    it "keeps a counted series whose rule cannot be expanded, reports it, and still lists the other events" do
      unreadable = ["FREQ=WEEKLY;BYWEEKNO=3;COUNT=2", "FREQ=DAILY;BYYEARDAY=400;COUNT=2", "FREQ=WEEKLY;INTERVAL=0;COUNT=2", "FREQ=MONTHLY;BYMONTH=13;COUNT=2"]
      vevents = unreadable.each_with_index.map do |rule, i|
        vevent("bad#{i}", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:Bad #{i}", "RRULE:#{rule}"])
      end
      stub_request(:get, url).to_return(status: 200, body: ics(*vevents, vevent("fine", ["DTSTART:20270115T150000Z", "DTEND:20270115T160000Z", "SUMMARY:Fine"])))
      events = nil
      reports = reported_ics_problems { events = parse_ics_calendar(url).first[:events] }
      expect(events.map { |e| e[:id] }).to eq(%w[bad0 bad1 bad2 bad3 fine])
      expect(reports.map { |_, context| context[:event_uid] }).to eq(%w[bad0 bad1 bad2 bad3])
      expect(reports.map { |_, context| context[:error_class] }).to all(eq("ArgumentError"))
      expect(reports.map(&:first)).to eq(
        ["Invalid rule validation type: BYWEEKNO", "by_year_day is out of range", "interval is out of range", "by_month is out of range"]
      )
    end

    {
      "FREQ=YEARLY;BYYEARDAY=0" => "by_year_day", "FREQ=YEARLY;BYYEARDAY=367" => "by_year_day", "FREQ=YEARLY;BYYEARDAY=-367" => "by_year_day",
      "FREQ=MONTHLY;BYMONTHDAY=0" => "by_month_day", "FREQ=MONTHLY;BYMONTHDAY=32" => "by_month_day", "FREQ=MONTHLY;BYMONTHDAY=-32" => "by_month_day",
      "FREQ=YEARLY;BYWEEKNO=0" => "by_week_number", "FREQ=YEARLY;BYWEEKNO=54" => "by_week_number", "FREQ=YEARLY;BYWEEKNO=-54" => "by_week_number",
      "FREQ=YEARLY;BYMONTH=0" => "by_month", "FREQ=YEARLY;BYMONTH=13" => "by_month",
      "FREQ=MONTHLY;BYDAY=MO;BYSETPOS=0" => "by_set_position", "FREQ=MONTHLY;BYDAY=MO;BYSETPOS=367" => "by_set_position",
      "FREQ=MONTHLY;BYDAY=MO;BYSETPOS=-367" => "by_set_position",
      "FREQ=MONTHLY;BYDAY=0MO" => "by_day", "FREQ=MONTHLY;BYDAY=54MO" => "by_day", "FREQ=MONTHLY;BYDAY=-54FR" => "by_day",
      "FREQ=WEEKLY;INTERVAL=0" => "interval"
    }.each do |rule, part|
      it "keeps the series and reports it when #{rule} has a value outside its allowed range" do
        body = ics(vevent("odd", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:Odd", "RRULE:#{rule};COUNT=2"]))
        stub_request(:get, url).to_return(status: 200, body: body)
        events = nil
        reports = reported_ics_problems { events = parse_ics_calendar(url).first[:events] }
        expect(events.map { |e| e[:id] }).to eq(["odd"])
        expect(reports.map(&:first)).to eq(["#{part} is out of range"])
      end
    end

    ["FREQ=WEEKLY;BYDAY=MO,TU,TH;COUNT=6", "FREQ=MONTHLY;BYDAY=1MO,-1FR;COUNT=6"].each do |rule|
      it "lists #{rule} without reporting its weekday list" do
        body = ics(vevent("days", ["DTSTART:20261201T150000Z", "DTEND:20261201T160000Z", "SUMMARY:Days", "RRULE:#{rule}"]))
        stub_request(:get, url).to_return(status: 200, body: body)
        events = nil
        reports = reported_ics_problems { events = parse_ics_calendar(url).first[:events] }
        expect(reports).to eq([])
        expect(events.map { |e| e[:id] }).to eq(["days"])
        expect(events.first[:rrule]).to include("BYDAY=#{rule[/BYDAY=([^;]+)/, 1]}")
      end
    end

    describe "the allowed ranges of a repeat rule" do
      let(:rule_class) { Struct.new(:interval, :by_day, :by_year_day, :by_month_day, :by_week_number, :by_month, :by_set_position, keyword_init: true) }

      def out_of_range(**parts)
        send(:out_of_range_rule_part, rule_class.new(**parts))
      end

      it "accepts the values at the edges of every range" do
        expect(out_of_range(interval: 1, by_day: %w[MO -1FR +53SU 5TU], by_year_day: %w[1 -1 366 -366], by_month_day: %w[1 -31 31],
                            by_week_number: %w[1 53 -53], by_month: %w[1 12], by_set_position: %w[1 -1 366 -366])).to be_nil
        expect(out_of_range).to be_nil
      end

      it "refuses a value that is not a number" do
        expect(out_of_range(by_month_day: %w[x])).to eq(:by_month_day)
        expect(out_of_range(by_set_position: ["1.5"])).to eq(:by_set_position)
        expect(out_of_range(by_day: ["1"])).to eq(:by_day)
      end
    end

    it "does not expand a series whose COUNT is above the limit, so it is kept without a report" do
      body = ics(vevent("long", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:Long", "RRULE:FREQ=DAILY;COUNT=#{CalendarHelper::MAX_COUNTED_SERIES + 1}"]))
      stub_request(:get, url).to_return(status: 200, body: body)
      expect(RecurrenceExpansion).not_to receive(:occurrences)
      events = nil
      expect(reported_ics_problems { events = parse_ics_calendar(url).first[:events] }).to eq([])
      expect(events.map { |e| e[:id] }).to eq(["long"])
    end

  end

  describe "#parse_ics_calendar with all-day events" do
    let(:url) { "https://calendar.example/all-day.ics" }

    def ics(*vevents)
      (["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//spec//EN"] + vevents.flatten + ["END:VCALENDAR"]).join("\r\n") + "\r\n"
    end

    def vevent(uid, lines)
      ["BEGIN:VEVENT", "UID:#{uid}", "DTSTAMP:20260101T000000Z", *lines, "END:VEVENT"]
    end

    def events_for(body, now: Time.utc(2026, 10, 28, 16, 0))
      stub_request(:get, url).to_return(status: 200, body: body)
      travel_to(now) { parse_ics_calendar(url).first[:events] }
    end

    def in_process_zone(zone)
      original = ENV["TZ"]
      ENV["TZ"] = zone
      yield
    ensure
      ENV["TZ"] = original
    end

    %w[UTC America/Toronto America/Vancouver].each do |zone|
      context "when the process zone is #{zone}" do
        around { |example| in_process_zone(zone) { example.run } }

        it "keeps a single all-day date on that date, with the exclusive end on the next date" do
          events = events_for(ics(vevent("one", ["DTSTART;VALUE=DATE:20261030", "DTEND;VALUE=DATE:20261031", "SUMMARY:Closed"])))
          expect(events.first).to include(allDay: true, start: "2026-10-30T00:00:00", end: "2026-10-31T00:00:00")
        end

        it "keeps a multi-day all-day span on its dates, ending on the exclusive end date" do
          events = events_for(ics(vevent("span", ["DTSTART;VALUE=DATE:20261030", "DTEND;VALUE=DATE:20261102", "SUMMARY:Break"])))
          expect(events.first).to include(allDay: true, start: "2026-10-30T00:00:00", end: "2026-11-02T00:00:00")
        end

        it "keeps all-day dates on the days clocks change" do
          body = ics(
            vevent("spring", ["DTSTART;VALUE=DATE:20260308", "DTEND;VALUE=DATE:20260309", "SUMMARY:Spring"]),
            vevent("fall", ["DTSTART;VALUE=DATE:20261101", "DTEND;VALUE=DATE:20261102", "SUMMARY:Fall"])
          )
          events = events_for(body, now: Time.utc(2026, 3, 1, 12, 0)).index_by { |e| e[:title].to_s }
          expect(events["Spring"]).to include(start: "2026-03-08T00:00:00", end: "2026-03-09T00:00:00")
          fall = events_for(body, now: Time.utc(2026, 10, 28, 12, 0)).index_by { |e| e[:title].to_s }["Fall"]
          expect(fall).to include(start: "2026-11-01T00:00:00", end: "2026-11-02T00:00:00")
        end

        it "keeps the dates of a recurring all-day series, its exceptions and its end" do
          body = ics(vevent("series", ["DTSTART;VALUE=DATE:20261030", "DTEND;VALUE=DATE:20261031", "SUMMARY:Weekly",
                                       "RRULE:FREQ=WEEKLY;UNTIL=20261231", "EXDATE;VALUE=DATE:20261106"]))
          event = events_for(body).first
          expect(event[:start]).to eq("2026-10-30T00:00:00")
          expect(event[:rrule]).to eq("DTSTART:20261030T000000\nRRULE:FREQ=WEEKLY;UNTIL=20261231T000000\nEXDATE:20261106T000000")
        end

        it "reads a floating time as Toronto wall-clock time" do
          body = ics(vevent("floating", ["DTSTART:20261030T090000", "DTEND:20261030T100000", "SUMMARY:Open"]))
          expect(events_for(body).first).to include(allDay: false, start: "2026-10-30T09:00:00", end: "2026-10-30T10:00:00")
        end

        it "reads floating times on the days clocks change as Toronto wall-clock time" do
          spring = ics(vevent("spring", ["DTSTART:20260308T090000", "DTEND:20260308T170000", "SUMMARY:Spring"]))
          expect(events_for(spring, now: Time.utc(2026, 3, 1, 12, 0)).first).to include(start: "2026-03-08T09:00:00", end: "2026-03-08T17:00:00")
          fall = ics(vevent("fall", ["DTSTART:20261101T090000", "DTEND:20261101T170000", "SUMMARY:Fall"]))
          expect(events_for(fall).first).to include(start: "2026-11-01T09:00:00", end: "2026-11-01T17:00:00")
        end

        it "keeps a floating recurring series, its exceptions and its end in Toronto wall-clock time" do
          body = ics(vevent("series", ["DTSTART:20261030T090000", "DTEND:20261030T100000", "SUMMARY:Weekly",
                                       "RRULE:FREQ=WEEKLY;UNTIL=20261231T235959", "EXDATE:20261106T090000"]))
          event = events_for(body).first
          expect(event[:start]).to eq("2026-10-30T09:00:00")
          expect(event[:rrule]).to eq("DTSTART:20261030T090000\nRRULE:FREQ=WEEKLY;UNTIL=20261231T235959\nEXDATE:20261106T090000")
          expect(event[:duration]).to eq(3_600_000)
        end

        it "leaves timed events on their own instant" do
          body = ics(vevent("timed", ["DTSTART:20261030T150000Z", "DTEND:20261030T160000Z", "SUMMARY:Open"]))
          expect(events_for(body).first).to include(allDay: false, start: "2026-10-30T11:00:00", end: "2026-10-30T12:00:00")
        end
      end
    end
  end

  describe "#safe_to_time" do
    it "keeps the instant of a date-time that has an offset" do
      expect(safe_to_time(DateTime.new(2026, 11, 1, 9, 0, 0, "+02:00"))).to eq(Time.utc(2026, 11, 1, 7, 0))
    end

    it "reads a date-time with no offset as Toronto wall-clock time" do
      expect(safe_to_time(DateTime.new(2026, 10, 30, 9, 0, 0))).to eq(Time.utc(2026, 10, 30, 13, 0))
    end

    it "reads a time zone name it cannot resolve as Toronto, and keeps one it can resolve" do
      body = ["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT", "UID:z", "DTSTAMP:20260101T000000Z",
              "DTSTART;TZID=Bogus/Zone:20261030T013000", "DTEND;TZID=Bogus/Zone:20261030T023000",
              "END:VEVENT", "BEGIN:VEVENT", "UID:p", "DTSTAMP:20260101T000000Z",
              "DTSTART;TZID=Europe/Paris:20261030T013000", "DTEND;TZID=Europe/Paris:20261030T023000",
              "END:VEVENT", "END:VCALENDAR"].join("\r\n") + "\r\n"
      events = Icalendar::Calendar.parse(body).first.events.index_by { |e| e.uid.to_s }
      expect(safe_to_time(events["z"].dtstart)).to eq(Time.utc(2026, 10, 30, 5, 30))
      expect(safe_to_time(events["p"].dtstart)).to eq(Time.utc(2026, 10, 30, 0, 30))
    end
  end

  describe "#generate_color_from_id" do
    it "gives the same colour for the same id, as rgba with the given opacity" do
      expect(generate_color_from_id("abc", 0.5)).to eq(generate_color_from_id("abc", 0.5))
      expect(generate_color_from_id("abc", 0.5)).to match(/\Argba\(\d+, \d+, \d+, 0\.5\)\z/)
    end

    it "reads a numeric id as the number and a text id from its bytes" do
      expect(generate_color_from_id("7")).to eq(generate_color_from_id(7))
      expect(generate_color_from_id("0")).to match(/\Argba/)
      expect(generate_color_from_id("7x")).to eq(generate_color_from_id("7"))
      expect(generate_color_from_id("abc")).not_to eq(generate_color_from_id("abd"))
    end

    it "never goes lighter than a 3:1 contrast against white, across all six hue sectors" do
      colors = (1..200).map { |i| generate_color_from_id(i) }
      colors.each do |c|
        r, g, b = c.scan(/\d+/).first(3).map(&:to_i)
        expect(contrast_with_white(r, g, b)).to be >= 3.0
      end
      expect(colors.uniq.size).to be > 100
    end
  end

  describe "#contrast_with_white" do
    it "is 1 for white and 21 for black, using both luminance branches" do
      expect(contrast_with_white(255, 255, 255)).to be_within(0.001).of(1.0)
      expect(contrast_with_white(0, 0, 0)).to be_within(0.001).of(21.0)
      expect(contrast_with_white(5, 5, 5)).to be > 15
    end
  end

  describe "#convert_rrule_to_string" do
    it "joins every present part, the end in Toronto wall-clock time, and leaves an interval of one out" do
      rule = OpenStruct.new(frequency: "WEEKLY", interval: 1, by_day: %w[MO WE], by_month_day: [1, 2], by_month: [3],
                            by_year_day: [100], by_week_number: [5], by_set_position: [-1],
                            until: Time.utc(2027, 6, 1, 12), count: 5, week_start: "SU")
      expect(convert_rrule_to_string(rule)).to eq(
        "FREQ=WEEKLY;BYDAY=MO,WE;BYMONTHDAY=1,2;BYMONTH=3;BYYEARDAY=100;BYWEEKNO=5;BYSETPOS=-1;" \
        "UNTIL=20270601T080000;COUNT=5;WKST=SU"
      )
    end

    it "writes an interval other than one and skips empty and missing parts" do
      rule = OpenStruct.new(frequency: "DAILY", interval: 3, by_day: [], by_month_day: nil, until: nil, count: nil, week_start: nil)
      expect(convert_rrule_to_string(rule)).to eq("FREQ=DAILY;INTERVAL=3")
      expect(convert_rrule_to_string(OpenStruct.new)).to eq("")
    end

    it "leaves UNTIL out when it cannot be read as a time" do
      unreadable = Object.new
      def unreadable.to_s = "never"
      expect(convert_rrule_to_string(OpenStruct.new(frequency: "DAILY", until: unreadable))).to eq("FREQ=DAILY")
    end
  end

  describe "#date_formatted_recurrence_rule" do
    let(:start_time) { Time.utc(2027, 5, 5, 13, 0) }

    it "is nil without a recurrence rule" do
      expect(date_formatted_recurrence_rule(OpenStruct.new(recurrence_rule: nil))).to be_nil
      expect(date_formatted_recurrence_rule(OpenStruct.new(recurrence_rule: ""))).to be_nil
    end

    it "rebuilds DTSTART in Toronto time and puts each EXDATE on its own line" do
      event = OpenStruct.new(start_time: start_time,
                             recurrence_rule: "DTSTART:20270505T130000Z\nRRULE:FREQ=WEEKLY;BYDAY=WE\nEXDATE:20270512T130000Z")
      expect(date_formatted_recurrence_rule(event)).to eq("DTSTART:20270505T090000\nRRULE:FREQ=WEEKLY;BYDAY=WE\nEXDATE:20270512T090000")
    end

    it "keeps a rule without exdates as it is after the new DTSTART" do
      event = OpenStruct.new(start_time: start_time, recurrence_rule: "RRULE:FREQ=DAILY;COUNT=2")
      expect(date_formatted_recurrence_rule(event)).to eq("DTSTART:20270505T090000\nRRULE:FREQ=DAILY;COUNT=2")
    end
  end

  describe "#combine_date_and_time" do
    it "keeps the Toronto date and takes the Toronto clock time" do
      # 01:02Z on 2027-05-06 is the evening of 2027-05-05 in Toronto; 13:45Z in January is 8:45 standard time
      result = combine_date_and_time(Time.utc(2027, 5, 6, 1, 2, 3), Time.utc(2020, 1, 1, 13, 45, 30))
      expect(result).to eq(Time.utc(2027, 5, 5, 12, 45, 30))
      expect(result.time_zone.name).to eq("America/Toronto")
    end
  end

  describe "#safe_to_time" do
    it "is nil for nil and for text that is not a time" do
      expect(safe_to_time(nil)).to be_nil
      expect(safe_to_time(Object.new.tap { |o| def o.to_time = raise(ArgumentError, "bad") })).to be_nil
      unreadable = Object.new
      def unreadable.to_s = "never"
      expect(safe_to_time(unreadable)).to be_nil
    end

    it "does not hide an error that is not about the value being a time" do
      broken = Object.new.tap { |o| def o.to_time = raise("bug") }
      expect { safe_to_time(broken) }.to raise_error("bug")
    end

    it "returns UTC for a time, a non-UTC time and a date" do
      expect(safe_to_time(Time.utc(2027, 1, 1, 5))).to eq(Time.utc(2027, 1, 1, 5))
      zoned = Time.new(2027, 1, 1, 5, 0, 0, "-05:00")
      expect(safe_to_time(zoned)).to eq(Time.utc(2027, 1, 1, 10))
      expect(safe_to_time(zoned)).to be_utc
      expect(safe_to_time(Date.new(2027, 1, 1)).utc?).to be(true)
    end

    it "is nil for a string that is not a time, and parses one that is" do
      expect(safe_to_time("garbage")).to be_nil
      expect(safe_to_time("2027-01-01 05:00:00 UTC")).to eq(Time.utc(2027, 1, 1, 5))
    end

    it "is nil for a value that cannot be a time" do
      expect(safe_to_time(Object.new)).to be_nil
    end

    it "is nil for a value that is neither text nor a time, even when its text reads as one" do
      value = Object.new
      def value.to_s = "2027-01-01 05:00:00 UTC"
      expect(safe_to_time(value)).to be_nil
    end
  end

  describe "#convert_to_js_rrule" do
    it "maps every present field to the JS rrule keys, shortening the weekdays to two letters" do
      rule = OpenStruct.new(frequency: "WEEKLY", interval: 2, by_day: %w[MO WE], until: "2027-06-01", count: 4,
                            by_hour: [9], by_month: [1], week_start: "SU")
      expect(convert_to_js_rrule(rule)).to eq(
        freq: "weekly", interval: 2, byweekday: %w[mo we], until: "2027-06-01", count: 4,
        by_hour: [9], by_month: [1], wkst: "SU"
      )
    end

    it "is empty for a rule with nothing set" do
      expect(convert_to_js_rrule(OpenStruct.new)).to eq({})
    end
  end
end
