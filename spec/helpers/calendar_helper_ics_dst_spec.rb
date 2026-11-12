# frozen_string_literal: true

require "rails_helper"

# What CalendarHelper#ics_feed builds from an imported calendar (ICS) for series that cross the two America/Toronto
# clock changes of 2027 (forward Sunday 2027-03-14 at 02:00, back Sunday 2027-11-07 at 02:00). Every calendar page
# that shows an imported calendar (admin unavailabilities, admin imported calendars, staff unavailabilities and the
# public open hours) reads this output. The files are in spec/fixtures/files/ics; the rows are also saved in
# spec/fixtures/files/ics/feed_events.json, which spec/javascript/calendars/rrule_feed_dst.test.js draws the way the
# browser does and spec/requests/calendar_rrule_feed_dst_request_spec.rb checks each feed against.
#
# These examples pin today's behaviour, including where it disagrees with what the file means. Each disagreement
# has a name in the comment above the example; the slices that move imported calendars onto the server's own
# expansion change those examples and rename nothing else.
RSpec.describe CalendarHelper, type: :helper do
  include ActiveSupport::Testing::TimeHelpers

  let(:feed_url) { "https://calendar.example.test/feed.ics" }
  let(:toronto) { ActiveSupport::TimeZone["America/Toronto"] }
  let(:saved_rows) { JSON.parse(Rails.root.join("spec/fixtures/files/ics/feed_events.json").read) }

  around { |example| travel_to(Time.utc(2027, 2, 1, 12)) { example.run } }

  # The feed built from a fixture, with the fetch stubbed at the boundary. Rows leave out the parts that do not
  # depend on the file (the source digest, the calendar name and the display mode).
  def rows_for(fixture)
    body = Rails.root.join("spec/fixtures/files/ics/#{fixture}.ics").binread
    allow(IcsFetcher).to receive(:get).with(feed_url, timeout: 10).and_return(body)
    feed = ics_feed(feed_url, name: "Hours")
    expect(feed).not_to be_failed
    feed.calendars.flat_map { |calendar| calendar[:events] }
        .map { |event| event.except(:groupId, :extendedProps, :display).deep_stringify_keys }
  end

  def row(rows, id) = rows.find { |r| r["id"] == id }

  # The occurrences the server's own engine (used by the staff calendar and the shifts API) gives for a rule text, in
  # Toronto time, starting at the Toronto wall time `from`.
  def server_occurrences(rule, start, count: 12)
    series_starts(rule, start, start, start + 200.days, count)
  end

  def starts(times) = times.map { |time| time.in_time_zone(toronto).strftime("%Y-%m-%dT%H:%M") }

  def toronto_start(row) = toronto.parse(row["start"])

  # To regenerate the saved rows after changing a fixture or the helper, run
  #   REGENERATE_FEED_EVENTS=1 bundle exec rspec spec/helpers/calendar_helper_ics_dst_spec.rb
  # and review the diff of spec/fixtures/files/ics/feed_events.json.
  it "is the same output as the rows saved for the browser spec" do
    fixtures = Dir[Rails.root.join("spec/fixtures/files/ics/*.ics")].map { |path| File.basename(path, ".ics") }.sort
    if ENV["REGENERATE_FEED_EVENTS"] == "1"
      rows = fixtures.to_h { |fixture| [fixture, rows_for(fixture)] }
      Rails.root.join("spec/fixtures/files/ics/feed_events.json").write("#{JSON.pretty_generate(rows)}\n")
      next
    end

    saved_rows.each do |fixture, saved|
      expect(rows_for(fixture)).to eq(saved),
                                   "#{fixture} differs from feed_events.json; regenerate it with " \
                                   "REGENERATE_FEED_EVENTS=1 bundle exec rspec spec/helpers/calendar_helper_ics_dst_spec.rb"
    end
  end

  describe "a calendar in the Toronto zone" do
    let(:rows) { rows_for("toronto_tzid") }

    it "sends the first occurrence's Toronto wall time as a floating repeat rule, with the length in milliseconds" do
      expect(row(rows, "spring-0230@ics.test")).to include(
        "start" => "2027-03-07T02:30:00", "end" => "2027-03-07T03:30:00", "allDay" => false,
        "rrule" => "DTSTART:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU", "duration" => 3_600_000
      )
      expect(row(rows, "fall-0130@ics.test")).to include(
        "rrule" => "DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU", "duration" => 3_600_000
      )
    end

    # Disagreement, named "skipped hour": the browser repeats the wall time 02:30, so it draws the series at 02:30 on
    # 2027-03-14, an hour that does not exist; the server's engine moves that occurrence to 03:30.
    it "gives a repeat rule the server expands to 03:30 on the day the clocks go forward" do
      spring = row(rows, "spring-0230@ics.test")
      expect(starts(server_occurrences(spring["rrule"], toronto_start(spring), count: 4)))
        .to eq(%w[2027-03-07T02:30 2027-03-14T03:30 2027-03-21T02:30 2027-03-28T02:30])
    end

    it "gives a repeat rule the server expands to the first 01:30 only on the day the clocks go back" do
      fall = row(rows, "fall-0130@ics.test")
      expect(starts(server_occurrences(fall["rrule"], toronto_start(fall), count: 4)))
        .to eq(%w[2027-10-31T01:30 2027-11-07T01:30 2027-11-14T01:30 2027-11-21T01:30])
    end
  end

  describe "a calendar in the Europe/Paris zone" do
    let(:rows) { rows_for("paris_tzid") }

    # Disagreement, named "calendar zone dropped": the file's 09:00 in Paris is sent as 03:00 Toronto wall time (the
    # time in force on the first occurrence) and repeated at 03:00 whatever the clocks do. Paris changes its clocks
    # on 2027-03-28 and 2027-10-31, Toronto on 2027-03-14 and 2027-11-07, so in between 09:00 in Paris is 04:00 in
    # Toronto and the browser draws it an hour early.
    it "sends the Toronto wall time of the first occurrence and loses the zone" do
      expect(row(rows, "paris-spring@ics.test")).to include(
        "start" => "2027-03-07T03:00:00", "rrule" => "DTSTART:20270307T030000\nRRULE:FREQ=WEEKLY;BYDAY=SU"
      )
      expect(row(rows, "paris-fall@ics.test")).to include(
        "start" => "2027-10-24T03:00:00", "rrule" => "DTSTART:20271024T030000\nRRULE:FREQ=WEEKLY;BYDAY=SU"
      )
    end

    it "is repeated at 03:00 Toronto time, while 09:00 in Paris is 04:00 Toronto time for two weeks after each Toronto change" do
      paris = ActiveSupport::TimeZone["Europe/Paris"]
      in_paris = server_occurrences("FREQ=WEEKLY;BYDAY=SU", paris.local(2027, 3, 7, 9), count: 4)
      expect(starts(in_paris)).to eq(%w[2027-03-07T03:00 2027-03-14T04:00 2027-03-21T04:00 2027-03-28T03:00])

      sent = row(rows, "paris-spring@ics.test")
      expect(starts(server_occurrences(sent["rrule"], toronto_start(sent), count: 4)))
        .to eq(%w[2027-03-07T03:00 2027-03-14T03:00 2027-03-21T03:00 2027-03-28T03:00])

      in_paris = server_occurrences("FREQ=WEEKLY;BYDAY=SU", paris.local(2027, 10, 24, 9), count: 4)
      expect(starts(in_paris)).to eq(%w[2027-10-24T03:00 2027-10-31T04:00 2027-11-07T03:00 2027-11-14T03:00])
    end
  end

  describe "a calendar with a Windows zone name and its own VTIMEZONE" do
    let(:rows) { rows_for("windows_timezone") }

    it "reads the zone from the file and sends Toronto wall time like a Toronto calendar" do
      expect(row(rows, "windows-spring@ics.test")).to include(
        "start" => "2027-03-07T02:30:00", "rrule" => "DTSTART:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU"
      )
      expect(row(rows, "windows-fall@ics.test")).to include(
        "start" => "2027-10-31T01:30:00", "rrule" => "DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU"
      )
    end

    it "resolves the zone to Eastern time (the offset in force on the first occurrence is -05:00)" do
      event = Icalendar::Calendar.parse(Rails.root.join("spec/fixtures/files/ics/windows_timezone.ics").read).first.events.first
      expect(event.dtstart.value.utc_offset).to eq(-5 * 3600)
    end
  end

  describe "a calendar with no zone (floating times)" do
    let(:rows) { rows_for("floating") }

    it "reads the times as Toronto wall time" do
      expect(row(rows, "floating-spring@ics.test")).to include(
        "start" => "2027-03-07T02:30:00", "rrule" => "DTSTART:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU"
      )
      expect(row(rows, "floating-fall@ics.test")).to include(
        "start" => "2027-10-31T01:30:00", "rrule" => "DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU"
      )
    end
  end

  describe "all-day series (VALUE=DATE)" do
    let(:rows) { rows_for("all_day") }

    it "sends midnight starts, a one-day length and allDay" do
      expect(row(rows, "allday-spring@ics.test")).to include(
        "allDay" => true, "start" => "2027-03-07T00:00:00", "end" => "2027-03-08T00:00:00",
        "rrule" => "DTSTART:20270307T000000\nRRULE:FREQ=WEEKLY;BYDAY=SU", "duration" => 86_400_000
      )
    end

    it "sends a date exclusion as midnight wall time" do
      expect(row(rows, "allday-fall@ics.test")["rrule"])
        .to eq("DTSTART:20271031T000000\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20271107T000000")
    end

    # Disagreement, named "all-day length in seconds": the length is sent as 86 400 seconds, so measured as the
    # server's engine does (start plus the length) the all-day occurrence of the day the clocks go forward ends at
    # 01:00 the next day instead of at midnight, and is no longer a whole day.
    it "has a length that ends at 01:00 the day after the clocks go forward" do
      spring = row(rows, "allday-spring@ics.test")
      change_day = server_occurrences(spring["rrule"], toronto_start(spring), count: 2).last
      expect(change_day.iso8601).to eq("2027-03-14T00:00:00-05:00")
      expect((change_day + spring["duration"] / 1000).in_time_zone(toronto).iso8601).to eq("2027-03-15T01:00:00-04:00")
    end
  end

  describe "an exclusion in the hour the clocks repeat" do
    let(:rows) { rows_for("exdate_repeated_hour") }

    # Disagreement, named "repeated hour exclusion": the file excludes the second 01:30 (06:30Z), the first (05:30Z)
    # or the zoned wall time; all three are sent as the same wall time 01:30, which the browser reads as the whole
    # day.
    it "sends the first 01:30, the second 01:30 and the zoned wall time as the same exclusion" do
      sent = %w[exdate-utc exdate-first exdate-local].map { |name| row(rows, "#{name}@ics.test")["rrule"] }
      expect(sent.uniq).to eq(["DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20271107T013000"])
    end

    it "removes the change-day occurrence the file only excluded the second 01:30 of" do
      sent = row(rows, "exdate-utc@ics.test")
      expect(starts(server_occurrences(sent["rrule"], toronto_start(sent), count: 3)))
        .to eq(%w[2027-10-31T01:30 2027-11-14T01:30 2027-11-21T01:30])

      as_filed = "DTSTART:20271031T053000Z\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20271107T063000Z"
      expect(starts(server_occurrences(as_filed, toronto.local(2027, 10, 31, 1, 30), count: 3)))
        .to eq(%w[2027-10-31T01:30 2027-11-07T01:30 2027-11-14T01:30])
    end
  end

  describe "a modified instance (RECURRENCE-ID)" do
    let(:rows) { rows_for("recurrence_id_moved") }

    it "excludes the original date from the series and lists the moved instance once, as an event of its own" do
      expect(row(rows, "moved@ics.test")["rrule"]).to eq("DTSTART:20270307T100000\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20270314T100000")
      moved = row(rows, "moved@ics.test_1805032800")
      expect(moved).to include("title" => "Sunday class (moved to Monday)", "start" => "2027-03-15T14:00:00", "end" => "2027-03-15T15:00:00")
      expect(moved).not_to have_key("rrule")
      expect(rows.size).to eq(2)
    end
  end

  describe "a cancelled instance and a cancelled series (STATUS:CANCELLED)" do
    let(:rows) { rows_for("recurrence_id_cancelled") }

    # Disagreement, named "cancelled still drawn": STATUS is never read. The cancelled instance is sent as an event of
    # its own at the time it was cancelled for (so the date the series excludes is drawn anyway), and a cancelled
    # series is sent like a live one.
    it "sends the cancelled instance as an event" do
      expect(row(rows, "cancelled@ics.test")["rrule"]).to eq("DTSTART:20270307T100000\nRRULE:FREQ=WEEKLY;BYDAY=SU\nEXDATE:20270314T100000")
      expect(row(rows, "cancelled@ics.test_1805032800")).to include(
        "title" => "Sunday class (cancelled)", "start" => "2027-03-14T10:00:00", "end" => "2027-03-14T11:00:00"
      )
    end

    it "sends the cancelled series with its repeat rule" do
      expect(row(rows, "cancelled-series@ics.test")).to include(
        "title" => "Cancelled Monday series", "rrule" => "DTSTART:20270315T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO"
      )
    end
  end

  describe "a series with an end (UNTIL)" do
    let(:rows) { rows_for("until") }

    it "sends a date UNTIL as midnight Toronto wall time" do
      expect(row(rows, "until-date@ics.test")["rrule"])
        .to eq("DTSTART:20270307T000000\nRRULE:FREQ=WEEKLY;BYDAY=SU;UNTIL=20270328T000000")
    end

    it "sends a UTC UNTIL as Toronto wall time" do
      expect(row(rows, "until-utc@ics.test")["rrule"])
        .to eq("DTSTART:20270307T100000\nRRULE:FREQ=WEEKLY;BYDAY=SU;UNTIL=20270321T100000")
      expect(row(rows, "until-utc-fall@ics.test")["rrule"])
        .to eq("DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU;UNTIL=20271107T013000")
    end

    # The browser reads the bare UNTIL as the same wall time and includes the last day (3 occurrences in the file,
    # 3 drawn). The server's engine reads a date as the end of that Toronto day and a bare time as Toronto wall
    # time, so given the sent text it also keeps the last occurrence (it used to read the bare UNTIL as UTC and
    # drop it).
    it "gives a text the server's engine keeps whole" do
      date_until = row(rows, "until-date@ics.test")
      expect(starts(server_occurrences(date_until["rrule"], toronto_start(date_until)))).to eq(%w[2027-03-07T00:00 2027-03-14T00:00 2027-03-21T00:00 2027-03-28T00:00])

      utc_until = row(rows, "until-utc@ics.test")
      expect(starts(server_occurrences(utc_until["rrule"], toronto_start(utc_until)))).to eq(%w[2027-03-07T10:00 2027-03-14T10:00 2027-03-21T10:00])

      as_filed = "DTSTART:20270307T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=SU;UNTIL=20270321T140000Z"
      expect(starts(server_occurrences(as_filed, toronto.local(2027, 3, 7, 10)))).to eq(%w[2027-03-07T10:00 2027-03-14T10:00 2027-03-21T10:00])
    end
  end

  describe "a series with a COUNT" do
    let(:rows) { rows_for("count") }

    it "sends the count in the rule" do
      expect(row(rows, "count-spring@ics.test")["rrule"]).to eq("DTSTART:20270307T023000\nRRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=3")
      expect(row(rows, "count-fall@ics.test")["rrule"]).to eq("DTSTART:20271031T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=3")
    end

    it "counts the repeated hour once in the server's expansion" do
      fall = row(rows, "count-fall@ics.test")
      expect(starts(server_occurrences(fall["rrule"], toronto_start(fall)))).to eq(%w[2027-10-31T01:30 2027-11-07T01:30 2027-11-14T01:30])
    end
  end

  describe "a rule with BYSETPOS" do
    let(:rows) { rows_for("bysetpos") }

    it "sends the BYSETPOS part in the rule" do
      expect(row(rows, "last-weekday@ics.test")["rrule"])
        .to eq("DTSTART:20270226T090000\nRRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1")
      expect(row(rows, "second-sunday-march@ics.test")["rrule"]).to eq("DTSTART:20270214T023000\nRRULE:FREQ=MONTHLY;BYDAY=SU;BYSETPOS=2")
      expect(row(rows, "first-sunday-november@ics.test")["rrule"]).to eq("DTSTART:20271003T013000\nRRULE:FREQ=MONTHLY;BYDAY=SU;BYSETPOS=1")
    end

    # The server's engine honours BYSETPOS (it used to drop it without a message and list every weekday or Sunday).
    it "gives a text the server's engine expands with BYSETPOS applied" do
      last = row(rows, "last-weekday@ics.test")
      expect(starts(server_occurrences(last["rrule"], toronto_start(last), count: 4)))
        .to eq(%w[2027-02-26T09:00 2027-03-31T09:00 2027-04-30T09:00 2027-05-31T09:00])

      second = row(rows, "second-sunday-march@ics.test")
      expect(starts(server_occurrences(second["rrule"], toronto_start(second), count: 4)))
        .to eq(%w[2027-02-14T02:30 2027-03-14T03:30 2027-04-11T02:30 2027-05-09T02:30])
    end
  end
end
