# frozen_string_literal: true

require "rails_helper"

# D-SP29: calendar JSON endpoints across the two America/Toronto DST changes,
# with the clock frozen in the week of each change:
#   spring-forward Sun 2027-03-14 02:00 EST -> 03:00 EDT (02:xx does not exist)
#   fall-back      Sun 2026-11-01 02:00 EDT -> 01:00 EST (01:xx happens twice)
#
# The FullCalendar `allDay` flag was computed as `start.to_time == end.to_time - 1.day`.
# `to_time` keeps the zone, so subtracting a calendar day from an end at 02:xx on
# Mon 2027-03-15 builds the nonexistent 2027-03-14 02:xx and raises
# TZInfo::PeriodNotFound. The check now runs on TimeWithZone values, which shift
# a nonexistent time forward instead.
RSpec.describe "Calendar JSON across DST changes", type: :request do
  include SpacesSpecHelpers
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space) }
  let(:zone) { Time.zone }

  march_now = ActiveSupport::TimeZone["Eastern Time (US & Canada)"].local(2027, 3, 15, 12)
  november_now = ActiveSupport::TimeZone["Eastern Time (US & Canada)"].local(2026, 11, 2, 12)

  def local(*parts) = zone.local(*parts)

  # travel before login: the session expiry is relative to the clock at login.
  def at(now, role = :staff)
    travel_to(now)
    sign_in_as(role)
  end

  after { travel_back }

  describe "GET /staff/my_calendar/json/:id" do
    let(:feed) { "/staff/my_calendar/json/#{space.id}" }

    def rows_for(event) = response.parsed_body.select { |r| r["id"].start_with?("event-#{event.id}") }

    context "in the week of the spring-forward change (clock 2027-03-15)" do
      before { at(march_now) }

      it "expands a recurring event whose occurrence ends at 02:00 on Mon 2027-03-15 (default window)" do
        ev = create(:event, space: space, recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=3",
                            start_time: local(2027, 3, 8, 0), end_time: local(2027, 3, 8, 2))
        get feed
        expect(response).to have_http_status(:ok)
        expect(rows_for(ev).map { |r| [r["start"], r["end"], r["allDay"]] }).to eq([
          ["2027-03-08T00:00:00-05:00", "2027-03-08T02:00:00-05:00", false],
          ["2027-03-15T00:00:00-04:00", "2027-03-15T02:00:00-04:00", false],
          ["2027-03-22T00:00:00-04:00", "2027-03-22T02:00:00-04:00", false]
        ])
      end

      it "keeps that occurrence in a week window that starts after the series (it used to vanish silently)" do
        ev = create(:event, space: space, recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=3",
                            start_time: local(2027, 3, 8, 0, 30), end_time: local(2027, 3, 8, 2, 30))
        get feed, params: { start: "2027-03-14T00:00:00-05:00", end: "2027-03-21T00:00:00-04:00" }
        expect(response).to have_http_status(:ok)
        expect(rows_for(ev).map { |r| [r["start"], r["end"]] })
          .to eq([%w[2027-03-15T00:30:00-04:00 2027-03-15T02:30:00-04:00]])
      end

      it "renders a single event ending at 02:30 on Mon 2027-03-15" do
        ev = create(:event, space: space, start_time: local(2027, 3, 15, 1, 30), end_time: local(2027, 3, 15, 2, 30))
        get feed
        expect(response).to have_http_status(:ok)
        expect(rows_for(ev).map { |r| [r["start"], r["end"], r["allDay"]] })
          .to eq([["2027-03-15T01:30:00-04:00", "2027-03-15T02:30:00-04:00", false]])
      end

      it "moves a 02:30 occurrence on 2027-03-14 forward to 03:30 EDT and keeps 02:30 on the other days" do
        ev = create(:event, space: space, recurrence_rule: "RRULE:FREQ=DAILY;COUNT=4",
                            start_time: local(2027, 3, 13, 2, 30), end_time: local(2027, 3, 13, 3, 30))
        get feed, params: { start: "2027-03-12T00:00:00-05:00", end: "2027-03-19T00:00:00-04:00" }
        expect(rows_for(ev).map { |r| r["start"] }).to eq(%w[
          2027-03-13T02:30:00-05:00 2027-03-14T03:30:00-04:00 2027-03-15T02:30:00-04:00 2027-03-16T02:30:00-04:00
        ])
      end

      it "keeps a weekly 10:00 event at 10:00 local on both sides" do
        ev = create(:event, space: space, recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=3",
                            start_time: local(2027, 3, 7, 10), end_time: local(2027, 3, 7, 11))
        get feed
        expect(rows_for(ev).map { |r| [r["start"], r["end"]] }).to eq([
          %w[2027-03-07T10:00:00-05:00 2027-03-07T11:00:00-05:00],
          %w[2027-03-14T10:00:00-04:00 2027-03-14T11:00:00-04:00],
          %w[2027-03-21T10:00:00-04:00 2027-03-21T11:00:00-04:00]
        ])
      end

      it "still flags the 23-hour midnight-to-midnight day of the change as all-day" do
        ev = create(:event, space: space, start_time: local(2027, 3, 14), end_time: local(2027, 3, 15))
        get feed
        expect(rows_for(ev).map { |r| r["allDay"] }).to eq([true])
      end
    end

    context "in the week of the fall-back change (clock 2026-11-02)" do
      before { at(november_now) }

      it "renders events ending in the repeated hour and on the day after" do
        ev = create(:event, space: space, recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=2",
                            start_time: local(2026, 10, 26, 0), end_time: local(2026, 10, 26, 1, 30))
        single = create(:event, space: space, start_time: local(2026, 11, 2, 0, 30), end_time: local(2026, 11, 2, 1, 30))
        get feed
        expect(response).to have_http_status(:ok)
        expect(rows_for(ev).map { |r| r["start"] }).to eq(%w[2026-10-26T00:00:00-04:00 2026-11-02T00:00:00-05:00])
        expect(rows_for(single).map { |r| r["end"] }).to eq(%w[2026-11-02T01:30:00-05:00])
      end

      it "keeps 02:30 (not repeated in Toronto) and a weekly 10:00 event at the same local time on both sides" do
        night = create(:event, space: space, recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=3",
                               start_time: local(2026, 10, 25, 2, 30), end_time: local(2026, 10, 25, 3, 30))
        day = create(:event, space: space, recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=3",
                             start_time: local(2026, 10, 25, 10), end_time: local(2026, 10, 25, 11))
        get feed
        expect(rows_for(night).map { |r| r["start"] })
          .to eq(%w[2026-10-25T02:30:00-04:00 2026-11-01T02:30:00-05:00 2026-11-08T02:30:00-05:00])
        expect(rows_for(day).map { |r| r["start"] })
          .to eq(%w[2026-10-25T10:00:00-04:00 2026-11-01T10:00:00-05:00 2026-11-08T10:00:00-05:00])
      end

      it "still flags the 25-hour midnight-to-midnight day of the change as all-day" do
        ev = create(:event, space: space, start_time: local(2026, 11, 1), end_time: local(2026, 11, 2))
        get feed
        expect(rows_for(ev).map { |r| r["allDay"] }).to eq([true])
      end
    end
  end

  describe "GET /api/v1/spaces/:id/shifts" do
    let(:staff) { create(:user, :staff) }

    def shifts(from, to)
      get "/api/v1/spaces/#{space.id}/shifts",
          params: { start: from, end: to },
          headers: { "ACCEPT" => "application/json", "Authorization" => "Bearer #{ApiAccessToken.issue(staff).first}" }
    end

    def shift(attrs) = create(:event, { space: space, event_type: "shift", title: "Shift" }.merge(attrs))
    def rows_for(event) = response.parsed_body.select { |r| r["id"].start_with?("event-#{event.id}") }

    context "in the week of the spring-forward change" do
      before { travel_to(march_now) }

      it "expands a recurring shift whose occurrence ends at 02:30 on Mon 2027-03-15" do
        ev = shift(recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=3",
                   start_time: local(2027, 3, 8, 0, 30), end_time: local(2027, 3, 8, 2, 30))
        shifts("2027-03-01T00:00:00-05:00", "2027-04-01T00:00:00-04:00")
        expect(response).to have_http_status(:ok)
        expect(rows_for(ev).map { |r| [r["start"], r["end"], r["allDay"]] }).to eq([
          ["2027-03-08T00:30:00-05:00", "2027-03-08T02:30:00-05:00", false],
          ["2027-03-15T00:30:00-04:00", "2027-03-15T02:30:00-04:00", false],
          ["2027-03-22T00:30:00-04:00", "2027-03-22T02:30:00-04:00", false]
        ])
      end

      it "renders a single shift ending at 02:30 on Mon 2027-03-15" do
        ev = shift(start_time: local(2027, 3, 15, 1, 30), end_time: local(2027, 3, 15, 2, 30))
        shifts("2027-03-14T00:00:00-05:00", "2027-03-21T00:00:00-04:00")
        expect(response).to have_http_status(:ok)
        expect(rows_for(ev).map { |r| r["end"] }).to eq(%w[2027-03-15T02:30:00-04:00])
      end

      it "moves 02:30 on 2027-03-14 to 03:30 EDT and keeps a weekly 10:00 shift at 10:00" do
        night = shift(recurrence_rule: "RRULE:FREQ=DAILY;COUNT=3",
                      start_time: local(2027, 3, 13, 2, 30), end_time: local(2027, 3, 13, 3, 30))
        day = shift(recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=2",
                    start_time: local(2027, 3, 7, 10), end_time: local(2027, 3, 7, 11))
        shifts("2027-03-01T00:00:00-05:00", "2027-04-01T00:00:00-04:00")
        expect(rows_for(night).map { |r| r["start"] })
          .to eq(%w[2027-03-13T02:30:00-05:00 2027-03-14T03:30:00-04:00 2027-03-15T02:30:00-04:00])
        expect(rows_for(day).map { |r| r["start"] }).to eq(%w[2027-03-07T10:00:00-05:00 2027-03-14T10:00:00-04:00])
      end
    end

    context "in the week of the fall-back change" do
      before { travel_to(november_now) }

      it "renders shifts ending in the repeated hour, and keeps 02:30 and 10:00 at the same local time" do
        single = shift(start_time: local(2026, 11, 2, 0, 30), end_time: local(2026, 11, 2, 1, 30))
        night = shift(recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=2",
                      start_time: local(2026, 10, 25, 2, 30), end_time: local(2026, 10, 25, 3, 30))
        day = shift(recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=2",
                    start_time: local(2026, 10, 25, 10), end_time: local(2026, 10, 25, 11))
        shifts("2026-10-20T00:00:00-04:00", "2026-11-10T00:00:00-05:00")
        expect(response).to have_http_status(:ok)
        expect(rows_for(single).map { |r| r["end"] }).to eq(%w[2026-11-02T01:30:00-05:00])
        expect(rows_for(night).map { |r| r["start"] }).to eq(%w[2026-10-25T02:30:00-04:00 2026-11-01T02:30:00-05:00])
        expect(rows_for(day).map { |r| r["start"] }).to eq(%w[2026-10-25T10:00:00-04:00 2026-11-01T10:00:00-05:00])
      end
    end
  end

  # These endpoints send the stored row (rrule expansion happens in the browser),
  # so the allDay check runs on each row's own start/end.
  describe "row endpoints with an event / unavailability ending on the day after a change" do
    let(:staff) { create(:user, :staff) }

    def unavailabilities_of(body, user) = body.find { |s| s["id"] == user.id }["unavailabilities"]

    [
      ["spring-forward", march_now, [2027, 3, 15, 1, 30], [2027, 3, 15, 2, 30], [2027, 3, 14], [2027, 3, 15]],
      ["fall-back", november_now, [2026, 11, 2, 0, 30], [2026, 11, 2, 1, 30], [2026, 11, 1], [2026, 11, 2]]
    ].each do |label, now, s, e, day_start, day_end|
      context "#{label} (clock #{now.to_date})" do
        it "GET /admin/events/json/:id renders it and flags the midnight-to-midnight day as all-day" do
          ev = create(:event, space: space, start_time: local(*s), end_time: local(*e))
          all_day = create(:event, space: space, start_time: local(*day_start), end_time: local(*day_end))
          at(now, :admin)
          get json_admin_events_path(id: space.id)
          expect(response).to have_http_status(:ok)
          rows = response.parsed_body.flat_map { |g| g["events"] }.index_by { |r| r["id"] }
          expect(rows["event-#{ev.id}"]).to include("end" => local(*e).iso8601, "allDay" => false)
          expect(rows["event-#{all_day.id}"]["allDay"]).to be(true)
        end

        it "GET /admin/calendar/unavailabilities_json/:id and utc_unavailabilities_json/:id render it" do
          StaffSpace.create!(user: staff, space: space)
          u = create(:staff_unavailability, user: staff, start_time: local(*s), end_time: local(*e))
          whole = create(:staff_unavailability, user: staff, start_time: local(*day_start), end_time: local(*day_end))
          at(now, :admin)
          get unavailabilities_json_admin_calendar_index_path(id: space.id)
          expect(response).to have_http_status(:ok)
          rows = unavailabilities_of(response.parsed_body, staff).index_by { |r| r["id"] }
          expect(rows[u.id]).to include("end" => local(*e).strftime("%Y-%m-%dT%H:%M:%S"), "allDay" => false)
          expect(rows[whole.id]["allDay"]).to be(true)

          get utc_unavailabilities_json_admin_calendar_index_path(id: space.id)
          expect(response).to have_http_status(:ok)
          rows = unavailabilities_of(response.parsed_body, staff).index_by { |r| r["id"] }
          expect(rows[u.id]["allDay"]).to be(false)
          expect(rows[whole.id]["allDay"]).to be(true)
        end

        it "GET /staff/unavailabilities/json renders it" do
          me = at(now, :staff)
          u = create(:staff_unavailability, user: me, start_time: local(*s), end_time: local(*e))
          whole = create(:staff_unavailability, user: me, start_time: local(*day_start), end_time: local(*day_end))
          get json_staff_unavailabilities_path
          expect(response).to have_http_status(:ok)
          rows = response.parsed_body.index_by { |r| r["id"] }
          expect(rows[u.id]).to include("end" => local(*e).iso8601, "allDay" => false)
          expect(rows[whole.id]["allDay"]).to be(true)
        end
      end
    end
  end
end
