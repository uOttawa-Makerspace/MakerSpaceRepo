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
        # all-day dates are read as UTC midnight and rendered in Toronto
        expect(event[:start]).to eq("2025-11-15T19:00:00")
        expect(event[:end]).to eq("2025-11-16T19:00:00")
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

    it "returns no calendar at all (not an empty one) when the fetch gives no body" do
      stub_request(:get, url).to_return(status: 404, body: "")
      expect(parse_ics_calendar(url)).to eq([])
    end

    it "logs and returns no events for a body that is not a calendar" do
      stub_request(:get, url).to_return(status: 200, body: "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nBROKEN")
      allow(Rails.logger).to receive(:error)
      expect(parse_ics_calendar(url).first[:events]).to eq([])
      expect(Rails.logger).to have_received(:error).with(/ICS parse error for #{Regexp.escape(url)}/)
    end

    it "uses the given name, and groups the calendar under the md5 of its URL" do
      stub_request(:get, url).to_return(status: 200, body: ics(vevent("a", ["DTSTART:20270115T150000Z", "DTEND:20270115T160000Z", "SUMMARY:Open", "DESCRIPTION:Walk in"])))
      group = parse_ics_calendar(url, name: "Hours", color: "#abcdef").first
      expect(group).to include(id: Digest::MD5.hexdigest(url), color: "#abcdef")
      expect(group[:events].first).to include(title: "Open", allDay: false, start: "2027-01-15T10:00:00", end: "2027-01-15T11:00:00")
      expect(group[:events].first[:extendedProps]).to eq(name: "Hours", description: "Walk in")
    end

    it "drops a single event that ended more than two months ago and keeps a recurring one" do
      body = ics(
        vevent("old", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:Old"]),
        vevent("rec", ["DTSTART:20260801T150000Z", "DTEND:20260801T160000Z", "SUMMARY:Rec", "RRULE:FREQ=DAILY;COUNT=3"])
      )
      stub_request(:get, url).to_return(status: 200, body: body)
      expect(parse_ics_calendar(url).first[:events].map { |e| e[:id] }).to eq(["rec"])
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
      expect(lines[1]).to start_with("RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;UNTIL=20271231T000000Z")
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

    it "drops the whole feed when one recurring event has no start (the error is logged, not raised)" do
      body = ics(
        vevent("fine", ["DTSTART:20270115T150000Z", "DTEND:20270115T160000Z", "SUMMARY:Fine"]),
        vevent("nostart", ["DTEND:20270115T160000Z", "SUMMARY:Broken", "RRULE:FREQ=DAILY;COUNT=2"])
      )
      stub_request(:get, url).to_return(status: 200, body: body)
      allow(Rails.logger).to receive(:error)
      expect(parse_ics_calendar(url).first[:events]).to eq([])
      expect(Rails.logger).to have_received(:error).with(/ICS parse error for #{Regexp.escape(url)}/)
    end

    it "gives a recurring event without an end no end time and a negative duration" do
      body = ics(vevent("noend", ["DTSTART:20270115T150000Z", "SUMMARY:Open ended", "RRULE:FREQ=DAILY;COUNT=2"]))
      stub_request(:get, url).to_return(status: 200, body: body)
      event = parse_ics_calendar(url).first[:events].first
      expect(event[:end]).to be_nil
      expect(event[:start]).to eq("2027-01-15T10:00:00")
      expect(event[:duration]).to eq(-Time.utc(2027, 1, 15, 15).to_i * 1000)
    end

    it "lists a modified instance whose master event is not in the feed" do
      body = ics(vevent("orphan", ["RECURRENCE-ID;VALUE=DATE:20270112", "DTSTART;VALUE=DATE:20270112", "DTEND;VALUE=DATE:20270113", "SUMMARY:Alone"]))
      stub_request(:get, url).to_return(status: 200, body: body)
      events = parse_ics_calendar(url).first[:events]
      expect(events.map { |e| [e[:title], e[:allDay]] }).to eq([["Alone", true]])
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
    it "joins every present part and leaves an interval of one out" do
      rule = OpenStruct.new(frequency: "WEEKLY", interval: 1, by_day: %w[MO WE], by_month_day: [1, 2], by_month: [3],
                            by_year_day: [100], by_week_number: [5], by_set_position: [-1],
                            until: Time.utc(2027, 6, 1, 12), count: 5, week_start: "SU")
      expect(convert_rrule_to_string(rule)).to eq(
        "FREQ=WEEKLY;BYDAY=MO,WE;BYMONTHDAY=1,2;BYMONTH=3;BYYEARDAY=100;BYWEEKNO=5;BYSETPOS=-1;" \
        "UNTIL=20270601T120000Z;COUNT=5;WKST=SU"
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

  describe "#parse_rrule_and_dtstart" do
    it "splits the rule, the start (as UTC) and the other lines" do
      rrule, dtstart, rest = parse_rrule_and_dtstart("DTSTART:20270505T130000Z\nRRULE:FREQ=DAILY\nEXDATE:20270506T130000Z")
      expect(rrule).to eq("FREQ=DAILY")
      expect(dtstart).to eq(Time.utc(2027, 5, 5, 13))
      expect(rest).to eq(["EXDATE:20270506T130000Z"])
    end

    it "returns nil for a missing start or rule" do
      rrule, dtstart, rest = parse_rrule_and_dtstart("EXDATE:20270506T130000Z")
      expect([rrule, dtstart, rest]).to eq([nil, nil, ["EXDATE:20270506T130000Z"]])
    end
  end

  describe "#add_exdate_to_rrule" do
    it "appends the date as a UTC EXDATE line" do
      expect(add_exdate_to_rrule("RRULE:FREQ=DAILY", Time.utc(2027, 5, 6, 13))).to eq("RRULE:FREQ=DAILY\nEXDATE:20270506T130000Z")
    end

    it "returns the rule untouched when either input is blank" do
      expect(add_exdate_to_rrule("RRULE:FREQ=DAILY", nil)).to eq("RRULE:FREQ=DAILY")
      expect(add_exdate_to_rrule(nil, Time.utc(2027, 5, 6))).to be_nil
      expect(add_exdate_to_rrule("", Time.utc(2027, 5, 6))).to eq("")
    end
  end

  describe "#combine_date_and_time" do
    it "keeps the date and takes the clock time" do
      result = combine_date_and_time(Time.utc(2027, 5, 6, 1, 2, 3), Time.utc(2020, 1, 1, 13, 45, 30))
      expect(result).to eq(Time.utc(2027, 5, 6, 13, 45, 30))
    end
  end

  describe "#remove_until_from_rrule" do
    it "removes an UNTIL part ending in Z and leaves other rules alone" do
      expect(remove_until_from_rrule("FREQ=DAILY;UNTIL=20270601T120000Z;COUNT=2")).to eq("FREQ=DAILY;COUNT=2")
      expect(remove_until_from_rrule("FREQ=DAILY;COUNT=2")).to eq("FREQ=DAILY;COUNT=2")
    end
  end

  describe "#safe_to_time" do
    it "is nil for nil and for text that is not a time" do
      expect(safe_to_time(nil)).to be_nil
      expect(safe_to_time(Object.new.tap { |o| def o.to_time = raise("bad") })).to be_nil
      unreadable = Object.new
      def unreadable.to_s = "never"
      expect(safe_to_time(unreadable)).to be_nil
    end

    it "returns UTC for a time, a non-UTC time and a date" do
      expect(safe_to_time(Time.utc(2027, 1, 1, 5))).to eq(Time.utc(2027, 1, 1, 5))
      zoned = Time.new(2027, 1, 1, 5, 0, 0, "-05:00")
      expect(safe_to_time(zoned)).to eq(Time.utc(2027, 1, 1, 10))
      expect(safe_to_time(zoned)).to be_utc
      expect(safe_to_time(Date.new(2027, 1, 1)).utc?).to be(true)
    end

    it "parses a value that has no to_time" do
      value = Object.new
      def value.to_s = "2027-01-01 05:00:00 UTC"
      expect(safe_to_time(value)).to eq(Time.utc(2027, 1, 1, 5))
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
