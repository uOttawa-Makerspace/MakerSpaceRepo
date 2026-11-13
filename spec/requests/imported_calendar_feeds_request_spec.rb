# frozen_string_literal: true

require "rails_helper"

# The two feeds that send only imported (ICS) calendars: the public opening hours feed (/open_hours, drawn on the
# home and hours pages) and the admin calendar's imported calendars feed. Both send, for the range the calendar asks
# for (?start&end, see CalendarWindow), the occurrences the server expands (ImportedCalendar, RecurringSeries) as
# times with their Toronto offset; neither sends a repeat rule. The ICS files are in spec/fixtures/files/ics; the
# weeks are those of the 2027 clock changes (forward Sunday 2027-03-14, back Sunday 2027-11-07).
RSpec.describe "Imported calendar feeds", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include SpacesSpecHelpers

  let(:space) { create(:space, name: "Makerspace") }
  let(:feed_url) { "https://calendar.example.test/feed.ics" }
  let(:spring_week) { { start: "2027-03-14T00:00:00", end: "2027-03-21T00:00:00" } }
  let(:fall_week) { { start: "2027-11-07T00:00:00", end: "2027-11-14T00:00:00" } }

  around { |example| travel_to(Time.utc(2027, 2, 1, 12)) { example.run } }

  def serve(fixture)
    allow(IcsFetcher).to receive(:get).and_return(nil)
    allow(IcsFetcher).to receive(:get).with(feed_url, any_args)
                                      .and_return(Rails.root.join("spec/fixtures/files/ics/#{fixture}.ics").binread)
  end

  def epoch(*wall) = RecurrenceRule::ZONE.local(*wall).to_i

  def open_hours_calendar!
    create(:staff_needed_calendar, role: "open_hours", space: space, calendar_url: feed_url, color: "#123456")
  end

  def rows_of(path, range)
    get path, params: range
    expect(response).to have_http_status(:ok)
    response.parsed_body.flat_map { |source| source["events"] }
  end

  describe "GET /open_hours" do
    it "answers a guest, with one source per calendar and the occurrences of the range asked for" do
      open_hours_calendar!
      serve("toronto_tzid")

      get open_hours_path, params: spring_week

      expect(response).to have_http_status(:ok)
      source = response.parsed_body.sole
      expect(source.keys).to eq(%w[id color events])
      expect(source.values_at("id", "color")).to eq([Digest::MD5.hexdigest(feed_url), "#123456"])
      row = source["events"].sole
      expect(row).to eq(
        "id" => "spring-0230@ics.test@#{Time.utc(2027, 3, 14, 7, 30).to_i}", "groupId" => source["id"],
        "title" => "Spring 02:30", "display" => "auto", "allDay" => false,
        "start" => "2027-03-14T03:30:00-04:00", "end" => "2027-03-14T04:30:00-04:00",
        "extendedProps" => { "name" => "Makerspace", "description" => nil, "occurrenceStart" => "2027-03-14T07:30:00Z" }
      )
    end

    it "sends the current week when no range is given" do
      open_hours_calendar!
      serve("toronto_tzid")

      travel_back
      travel_to(Time.utc(2027, 11, 13, 16))
      get open_hours_path

      expect(response.parsed_body.sole["events"].map { |row| row["start"] }).to eq(%w[2027-11-07T02:30:00-05:00 2027-11-07T01:30:00-04:00])
    end

    it "answers 400 with the reason for a range it cannot read" do
      get open_hours_path, params: { start: "2027-03-14" }
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => I18n.t("errors.calendar.window_invalid"))

      get open_hours_path, params: { start: "2027-01-01", end: "2027-06-01" }
      expect(response).to have_http_status(:bad_request)
    end

    it "sends only the opening-hours calendars" do
      create(:staff_needed_calendar, role: nil, space: space, calendar_url: feed_url)
      serve("toronto_tzid")

      expect(rows_of(open_hours_path, spring_week)).to eq([])
      expect(IcsFetcher).not_to have_received(:get)
    end
  end

  # Each feed sends the same occurrences for the same file.
  { "the opening hours feed" => :open_hours, "the admin imported calendars feed" => :imported }.each do |feed, kind|
    describe feed do
      let(:path) { kind == :open_hours ? open_hours_path : imported_calendars_json_admin_calendar_index_path(id: space.id) }

      before do
        next open_hours_calendar! if kind == :open_hours

        create(:staff_needed_calendar, space: space, calendar_url: feed_url, name: "Hours", color: "#123456")
        sign_in_as(:admin)
      end

      def rows_for(fixture, range)
        serve(fixture)
        rows_of(path, range)
      end

      def starts(fixture, range) = rows_for(fixture, range).map { |row| [row["id"], row["start"], row["end"]] }

      it "moves a Toronto series' skipped 02:30 forward to 03:30 in the spring-forward week" do
        expect(starts("toronto_tzid", spring_week)).to eq([
          ["spring-0230@ics.test@#{epoch(2027, 3, 14, 3, 30)}", "2027-03-14T03:30:00-04:00", "2027-03-14T04:30:00-04:00"]
        ])
      end

      it "sends a Toronto series' 01:30 once, at its first instant, in the fall-back week, ending an hour later" do
        expect(starts("toronto_tzid", fall_week)).to eq([
          ["spring-0230@ics.test@#{epoch(2027, 11, 7, 2, 30)}", "2027-11-07T02:30:00-05:00", "2027-11-07T03:30:00-05:00"],
          ["fall-0130@ics.test@#{Time.utc(2027, 11, 7, 5, 30).to_i}", "2027-11-07T01:30:00-04:00", "2027-11-07T01:30:00-05:00"]
        ])
      end

      it "sends a moved instance once, at its new time, and leaves its original Sunday out" do
        expect(starts("recurrence_id_moved", spring_week)).to eq([
          ["moved@ics.test_#{epoch(2027, 3, 14, 10)}", "2027-03-15T14:00:00-04:00", "2027-03-15T15:00:00-04:00"]
        ])
      end

      it "leaves out a cancelled instance and a cancelled series" do
        expect(starts("recurrence_id_cancelled", spring_week)).to eq([])
        expect(starts("recurrence_id_cancelled", start: "2027-03-21T00:00:00", end: "2027-03-28T00:00:00").map(&:second))
          .to eq(%w[2027-03-21T10:00:00-04:00])
      end

      it "leaves out an exception date in the fall-back week: the first 01:30, the wall time, and the all-day date" do
        expect(starts("exdate_repeated_hour", fall_week).map(&:first)).to eq(["exdate-utc@ics.test@#{Time.utc(2027, 11, 7, 5, 30).to_i}"])
        expect(rows_for("all_day", fall_week).map { |row| row["id"] }).to eq(["allday-spring@ics.test@#{epoch(2027, 11, 7)}"])
      end

      it "sends an all-day occurrence of the spring-forward Sunday as dates" do
        row = rows_for("all_day", spring_week).sole
        expect(row.values_at("start", "end", "allDay")).to eq(["2027-03-14", "2027-03-15", true])
      end

      it "sends no repeat rule" do
        expect(rows_for("toronto_tzid", spring_week)).to all(satisfy { |row| !row.key?("rrule") && !row.key?("duration") })
      end
    end
  end

  describe "GET imported_calendars_json" do
    it "needs a range" do
      sign_in_as(:admin)
      get imported_calendars_json_admin_calendar_index_path(id: space.id)
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => I18n.t("errors.calendar.window_invalid"))
    end

    it "is for admins only" do
      sign_in_as(:staff)
      get imported_calendars_json_admin_calendar_index_path(id: space.id), params: spring_week
      expect(response).to redirect_to(root_path)
    end
  end
end
