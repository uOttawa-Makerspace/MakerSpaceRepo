# frozen_string_literal: true

require "rails_helper"

# Contract: doc/api/v1/shifts.md
RSpec.describe "GET /api/v1/spaces/:id/shifts", type: :request do
  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:regular) { create(:user) }
  let!(:space) { create(:space) }
  let(:other_space) { create(:space) }
  let(:t0) { Time.utc(2026, 11, 2, 14) } # a Monday

  def body = response.parsed_body
  def error = body["error"]
  def auth(user) = { "Authorization" => "Bearer #{ApiAccessToken.issue(user).first}" }
  def shifts(query = {}, id: space.id, as: staff)
    get "/api/v1/spaces/#{id}/shifts", params: query, headers: json_headers.merge(as ? auth(as) : {})
  end
  def window = { start: (t0 - 1.day).iso8601, end: (t0 + 7.days).iso8601 }
  def shift(attrs = {}) = create(:event, { space: space, event_type: "shift", title: "Shift", start_time: t0, end_time: t0 + 2.hours }.merge(attrs))

  it "401s a guest and 403s a regular user" do
    shifts(window, as: nil)
    expect(response).to have_http_status(:unauthorized)
    shifts(window, as: regular)
    expect(response).to have_http_status(:forbidden)
    expect(error["code"]).to eq("forbidden")
  end

  it "lists published shifts with the exact keys, for staff and admin" do
    a = create(:user, :staff, name: "Ann Staff")
    b = create(:user, :staff, name: "Bob Staff")
    StaffSpace.find_or_create_by!(user: a, space: space).update_columns(color: "#ff0000")
    ev = shift(description: "Front desk")
    EventAssignment.create!(event: ev, user: a)
    EventAssignment.create!(event: ev, user: b)
    [staff, admin].each do |caller|
      shifts(window, as: caller)
      expect(response).to have_http_status(:ok)
      expect(body.size).to eq(1)
      row = body.first
      expect(row.keys).to eq(%w[id title start end allDay extendedProps])
      expect(row["extendedProps"].keys).to eq(%w[eventType description background])
      expect(row).to include("id" => "event-#{ev.id}", "title" => "Shift for Ann Staff, Bob Staff", "allDay" => false)
      expect(row["start"]).to eq(t0.in_time_zone.iso8601)
      expect(row["end"]).to eq((t0 + 2.hours).in_time_zone.iso8601)
      expect(row["extendedProps"]).to include("eventType" => "shift", "description" => "Front desk")
      expect(row["extendedProps"]["background"]).to eq("linear-gradient(to right, #ff0000 0.0%, #ff0000 50.0%, #3788d8 50.0%, #3788d8 100.0%);")
    end
    expect(response.body).not_to include(a.email)
  end

  it "uses the default colour for an unassigned shift" do
    shift
    shifts(window)
    expect(body.first["extendedProps"]["background"]).to eq("#3788d8")
  end

  it "excludes drafts, other event types, other spaces and events outside the window" do
    keep = shift
    shift(draft: true)
    create(:event, space: space, event_type: "meeting", start_time: t0, end_time: t0 + 1.hour)
    create(:event, space: other_space, event_type: "shift", start_time: t0, end_time: t0 + 1.hour)
    shift(start_time: t0 + 30.days, end_time: t0 + 30.days + 1.hour)
    shift(start_time: t0 - 2.days, end_time: t0 + 1.hour) # straddles the window start: legacy needs it fully inside
    shifts(window)
    expect(body.map { |r| r["id"] }).to eq(["event-#{keep.id}"])
  end

  it "filters by user_id and leaves the other assignees in the title" do
    a = create(:user, :staff, name: "Ann Staff")
    b = create(:user, :staff, name: "Bob Staff")
    mine = shift
    EventAssignment.create!(event: mine, user: a)
    EventAssignment.create!(event: mine, user: b)
    theirs = shift(start_time: t0 + 1.day, end_time: t0 + 1.day + 1.hour)
    EventAssignment.create!(event: theirs, user: b)
    shifts(window.merge(user_id: a.id))
    expect(body.map { |r| r["id"] }).to eq(["event-#{mine.id}"])
    expect(body.first["title"]).to eq("Shift for Ann Staff, Bob Staff")
    shifts(window.merge(user_id: 0))
    expect(body).to eq([])
  end

  it "expands a recurring shift into its occurrences in the window" do
    ev = shift(recurrence_rule: "FREQ=WEEKLY;BYDAY=MO;COUNT=4")
    shifts({ start: t0.iso8601, end: (t0 + 15.days).iso8601 })
    expect(body.map { |r| r["id"] }).to eq([t0, t0 + 7.days, t0 + 14.days].map { |t| "event-#{ev.id}-#{t.to_i}" })
    expect(body.map { |r| r["start"] }).to eq([t0, t0 + 7.days, t0 + 14.days].map { |t| t.in_time_zone.iso8601 })
    expect(body.first["end"]).to eq((t0 + 2.hours).in_time_zone.iso8601)
  end

  it "does not query per event" do
    users = create_list(:user, 3, :staff)
    4.times do |i|
      ev = shift(start_time: t0 + i.hours, end_time: t0 + i.hours + 30.minutes)
      users.each { |u| EventAssignment.create!(event: ev, user: u) }
    end
    count = 0
    cb = ->(*, payload) { count += 1 if payload[:sql].match?(/FROM "(events|event_assignments|users|staff_spaces)"/) }
    token = auth(staff)
    ActiveSupport::Notifications.subscribed(cb, "sql.active_record") do
      get "/api/v1/spaces/#{space.id}/shifts", params: window, headers: json_headers.merge(token)
    end
    expect(body.size).to eq(4)
    expect(count).to be <= 7 # token user, space, events, assignments, users, staff_spaces, + slack
  end

  it "404s an unknown space and a non-integer id" do
    shifts(window, id: 0)
    expect(response).to have_http_status(:not_found)
    shifts(window, id: "abc")
    expect(response).to have_http_status(:not_found)
  end

  it "422s a missing, malformed, reversed or over-long window" do
    shifts({})
    expect(response).to have_http_status(:unprocessable_content)
    expect(error["fields"].keys).to match_array(%w[start end])
    shifts(window.merge(start: "yesterday"))
    expect(response).to have_http_status(:unprocessable_content)
    expect(error["fields"]).to have_key("start")
    shifts(window.merge(end: "2026-13-45T00:00:00Z"))
    expect(response).to have_http_status(:unprocessable_content)
    shifts({ start: (t0 + 1.day).iso8601, end: t0.iso8601 })
    expect(response).to have_http_status(:unprocessable_content)
    expect(error["fields"]).to have_key("end")
    shifts({ start: t0.iso8601, end: (t0 + 101.days).iso8601 })
    expect(response).to have_http_status(:unprocessable_content)
    shifts({ start: t0.iso8601, end: (t0 + 100.days).iso8601 })
    expect(response).to have_http_status(:ok)
    shifts(window.merge(user_id: "abc"))
    expect(response).to have_http_status(:unprocessable_content)
    expect(error["fields"]).to have_key("user_id")
  end

  describe "runaway recurrence rules" do
    let(:wide) { { start: t0.iso8601, end: (t0 + 100.days).iso8601 } }

    def timed
      t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
    end

    %w[MINUTELY SECONDLY].each do |freq|
      it "caps a FREQ=#{freq} event per event, quickly, and flags the truncation" do
        shift(recurrence_rule: "FREQ=#{freq}")
        elapsed = timed { shifts(wide) }
        expect(response).to have_http_status(:ok)
        expect(body.size).to eq(500)
        expect(response.headers["X-Truncated"]).to eq("true")
        expect(body.first.keys).to eq(%w[id title start end allDay extendedProps])
        expect(elapsed).to be < 2
      end
    end

    it "bounds the cost of a sub-hourly rule whose DTSTART is far in the past" do
      shift(recurrence_rule: "FREQ=MINUTELY", start_time: t0 - 2.years, end_time: t0 - 2.years + 1.hour)
      elapsed = timed { shifts({ start: t0.iso8601, end: (t0 + 1.day).iso8601 }) }
      expect(body.size).to eq(500)
      expect(elapsed).to be < 2
    end

    it "caps the whole response across events and keeps the earliest first" do
      stub_const("Api::V1::ShiftEventSerializer::MAX_ITEMS", 12)
      stub_const("Api::V1::ShiftEventSerializer::MAX_OCCURRENCES_PER_EVENT", 5)
      3.times { |i| shift(recurrence_rule: "FREQ=HOURLY", start_time: t0 + i.minutes) }
      shifts(wide)
      expect(body.size).to eq(12)
      expect(response.headers["X-Truncated"]).to eq("true")
    end

    it "sends no X-Truncated header and keeps all weekly/daily occurrences otherwise" do
      shift(recurrence_rule: "FREQ=WEEKLY;BYDAY=MO", start_time: t0, end_time: t0 + 1.hour)
      shift(recurrence_rule: "FREQ=DAILY;COUNT=3", start_time: t0, end_time: t0 + 1.hour)
      shifts(window.merge(end: (t0 + 27.days).iso8601))
      expect(response.headers).not_to have_key("X-Truncated")
      expect(body.size).to eq(4 + 3)
    end
  end
end
