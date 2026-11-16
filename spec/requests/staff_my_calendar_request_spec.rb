# frozen_string_literal: true

require "rails_helper"

# Staff::MyCalendarController (index page + JSON feed). The feed is built from
# Event rows (not Shift, which no controller uses). The app zone is Eastern;
# recurring events are expanded by RecurringSeries from the event's own start_time, so
# the wall-clock hour is kept across the DST jump (Sun 2027-03-14 in Toronto).
# travel_to goes BEFORE login: sessions expire (session[:expires_at]) relative to
# the clock at login time.

RSpec.describe "Staff my calendar", type: :request do
  include SpacesSpecHelpers
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space) }
  let(:feed) { "/staff/my_calendar/json/#{space.id}" }
  let(:window) { { start: "2027-03-07T00:00:00-05:00", end: "2027-03-21T00:00:00-04:00" } }

  describe "auth" do
    let(:calls) do
      { index: -> { get staff_my_calendar_index_path }, json: -> { get feed } }
    end

    it "sends a guest to login with back_to" do
      calls.each_value do |call|
        instance_exec(&call)
        expect(response).to have_http_status(:found)
        expect(response.location).to start_with("http://www.example.com/login?back_to=")
      end
    end

    it "sends a regular user to root with an alert" do
      expect_bounced(:regular, calls, state: -> { Event.count }, to: root_path, flash_alert: "You cannot access this area.")
    end
  end

  describe "index" do
    it "lists only the spaces the staff member is assigned to, preselecting their own space" do
      mine = create(:space, name: "Mine")
      create(:space, name: "NotMine")
      staff = sign_in_as(:staff)
      staff.update!(space_id: mine.id)
      create(:staff_space, user: staff, space: mine)
      get staff_my_calendar_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Work Schedule")
      expect(response.body).to include(%(<option selected="selected" value="#{mine.id}">Mine</option>))
      expect(response.body).not_to include("NotMine")
    end

    it "falls back to the first assigned space when the user has no space" do
      staff = sign_in_as(:staff)
      create(:staff_space, user: staff, space: space)
      get staff_my_calendar_index_path
      expect(response.body).to include(%(value="#{space.id}"))
    end

    it "falls back to the first assigned space when the user's own space is not one they are assigned to" do
      staff = sign_in_as(:staff)
      staff.update!(space_id: create(:space, name: "Elsewhere").id)
      create(:staff_space, user: staff, space: space)
      get staff_my_calendar_index_path
      expect(response.body).to include(%(<option selected="selected" value="#{space.id}">))
      expect(response.body).not_to include("Elsewhere")
    end

    it "shows an empty state, not an error, for staff assigned to no space" do
      sign_in_as(:staff)
      get staff_my_calendar_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("not assigned to any space")
      expect(response.body).not_to include('id="calendar"')
    end
  end

  describe "json feed" do
    around { |ex| travel_to(Time.zone.local(2027, 3, 12, 12)) { ex.run } }

    let!(:staff) { sign_in_as(:staff).tap { |user| create(:staff_space, user: user, space: space) } }

    it "serves the feed of the staff member's spaces only" do
      other_space = create(:space)
      create(:event, space: other_space, title: "Elsewhere", start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      get "/staff/my_calendar/json/#{other_space.id}", params: window
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("Elsewhere")
    end

    it "serves the feed of any space to an admin" do
      other_space = create(:space)
      create(:event, space: other_space, title: "Elsewhere", start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      sign_in_as(:admin)
      get "/staff/my_calendar/json/#{other_space.id}", params: window
      expect(response.parsed_body.map { |e| e["title"] }).to eq(["Elsewhere"])
    end

    it "returns the FullCalendar shape for a single event, excluding drafts" do
      single = create(:event, space: space, title: "Meet", description: "d", start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      create(:event, :draft, space: space, title: "Hidden", start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      get feed, params: window
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([{
        "id" => "event-#{single.id}", "title" => "Meet",
        "start" => "2027-03-13T09:00:00-05:00", "end" => "2027-03-13T10:00:00-05:00", "allDay" => false,
        "extendedProps" => { "name" => "Meeting", "draft" => false, "description" => "d", "eventType" => "meeting",
                             "hasCurrentUser" => false, "background" => "#3788d8" }
      }])
    end

    it "keeps wall-clock time across the spring-forward jump for recurring events" do
      create(:event, space: space, title: "Weekly", recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=4",
                     start_time: Time.zone.local(2027, 3, 7, 10), end_time: Time.zone.local(2027, 3, 7, 11))
      get feed, params: { start: "2027-03-01T00:00:00-05:00", end: "2027-04-01T00:00:00-04:00" }
      starts = response.parsed_body.map { |e| e["start"] }
      expect(starts).to eq(%w[2027-03-07T10:00:00-05:00 2027-03-14T10:00:00-04:00 2027-03-21T10:00:00-04:00 2027-03-28T10:00:00-04:00])
      expect(response.parsed_body.map { |e| e["id"] }.uniq.size).to eq(4)
      expect(response.parsed_body.first["id"]).to match(/\Aevent-\d+-\d+\z/)
    end

    it "leaves out an occurrence removed from the series with an EXDATE" do
      create(:event, space: space, title: "Weekly", recurrence_rule: "RRULE:FREQ=WEEKLY;BYDAY=SU;COUNT=4\nEXDATE:20270314T140000Z",
                     start_time: Time.zone.local(2027, 3, 7, 10), end_time: Time.zone.local(2027, 3, 7, 11))
      get feed, params: { start: "2027-03-01T00:00:00-05:00", end: "2027-04-01T00:00:00-04:00" }
      expect(response.parsed_body.map { |e| e["start"] }).to eq(%w[2027-03-07T10:00:00-05:00 2027-03-21T10:00:00-04:00 2027-03-28T10:00:00-04:00])
    end

    it "an event across the DST gap keeps its wall-clock endpoints (2h of clock time is 1h elapsed)" do
      create(:event, space: space, title: "Night", start_time: Time.zone.local(2027, 3, 14, 1, 30), end_time: Time.zone.local(2027, 3, 14, 3, 30))
      get feed, params: { start: "2027-03-14T00:00:00-05:00", end: "2027-03-15T00:00:00-04:00" }
      row = response.parsed_body.first
      expect([row["start"], row["end"]]).to eq(%w[2027-03-14T01:30:00-05:00 2027-03-14T03:30:00-04:00])
    end

    it "drops single events that only partly overlap the requested window" do
      create(:event, space: space, title: "Edge", start_time: Time.zone.local(2027, 3, 13, 23), end_time: Time.zone.local(2027, 3, 14, 1))
      get feed, params: { start: "2027-03-13T00:00:00-05:00", end: "2027-03-14T00:00:00-05:00" }
      expect(response.parsed_body).to eq([])
    end

    it "defaults the window to 50 days either side of now" do
      create(:event, space: space, title: "Soon", start_time: Time.zone.local(2027, 4, 1, 9), end_time: Time.zone.local(2027, 4, 1, 10))
      create(:event, space: space, title: "Far", start_time: Time.zone.local(2027, 9, 1, 9), end_time: Time.zone.local(2027, 9, 1, 10))
      create(:event, space: space, title: "Too far", start_time: Time.zone.local(2027, 6, 1, 9), end_time: Time.zone.local(2027, 6, 1, 10))
      get feed
      expect(response.parsed_body.map { |e| e["title"] }).to eq(["Soon"])
    end

    it "refuses a range over 100 days and accepts exactly 100" do
      create(:event, space: space, title: "Later", start_time: Time.zone.local(2029, 6, 1, 9), end_time: Time.zone.local(2029, 6, 1, 10))
      get feed, params: { start: "2027-01-01T00:00:00-05:00", end: "2030-01-01T00:00:00-05:00" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(I18n.t("errors.staff.my_calendar.range_too_long"))
      get feed, params: { start: "2029-05-01T00:00:00Z", end: "2029-08-09T00:00:00Z" }
      expect(response.parsed_body.map { |e| e["title"] }).to eq(["Later"])
    end

    it "derives a missing bound from the given one" do
      create(:event, space: space, title: "After", start_time: Time.zone.local(2029, 6, 1, 9), end_time: Time.zone.local(2029, 6, 1, 10))
      get feed, params: { start: "2029-05-01T00:00:00Z" }
      expect(response.parsed_body.map { |e| e["title"] }).to eq(["After"])
      get feed, params: { end: "2029-07-20T00:00:00Z" }
      expect(response.parsed_body.map { |e| e["title"] }).to eq(["After"])
      get feed, params: { start: "2029-07-01T00:00:00Z" }
      expect(response.parsed_body).to eq([])
    end

    it "accepts the derived and the full 100 day ranges across a clock change" do
      create(:event, space: space, title: "Spring", start_time: Time.zone.local(2027, 2, 1, 9), end_time: Time.zone.local(2027, 2, 1, 10))
      get feed, params: { end: "2027-05-10T00:00:00-04:00" }
      expect(response.parsed_body.map { |e| e["title"] }).to eq(["Spring"])
      get feed, params: { start: "2027-02-01T00:00:00-05:00", end: "2027-05-12T00:00:00-04:00" }
      expect(response).to have_http_status(:ok)
      get feed, params: { start: "2027-02-01T00:00:00-05:00", end: "2027-05-13T00:00:00-04:00" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts 100 local days across the autumn clock change and refuses one more" do
      get feed, params: { start: "2027-08-05T00:00:00-04:00", end: "2027-11-13T00:00:00-05:00" }
      expect(response).to have_http_status(:ok)
      get feed, params: { start: "2027-08-05T00:00:00-04:00", end: "2027-11-14T00:00:00-05:00" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "filters by event_type and by assigned user" do
      assigned = create(:user, :staff)
      a = create(:event, space: space, title: "A", event_type: "shift", start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      create(:event, space: space, title: "B", event_type: "meeting", start_time: Time.zone.local(2027, 3, 13, 11), end_time: Time.zone.local(2027, 3, 13, 12))
      EventAssignment.create!(event: a, user: assigned)
      get feed, params: window.merge(event_type: "meeting")
      expect(response.parsed_body.map { |e| e["title"] }).to eq(["B"])
      get feed, params: window.merge(user_id: assigned.id)
      expect(response.parsed_body.map { |e| e["id"] }).to eq(["event-#{a.id}"])
    end

    it "colours assigned events by StaffSpace colour and flags the current user" do
      mate = create(:user, :staff)
      StaffSpace.find_by!(user: staff, space: space).update_column(:color, "#111111")
      create(:staff_space, user: mate, space: space).update_column(:color, "#222222")
      ev = create(:event, space: space, title: "Duo", start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      [staff, mate].each { |u| EventAssignment.create!(event: ev, user: u) }
      get feed, params: window
      props = response.parsed_body.first["extendedProps"]
      expect(props["hasCurrentUser"]).to be(true)
      expect(props["background"]).to eq("linear-gradient(to right, #111111 0.0%, #111111 50.0%, #222222 50.0%, #222222 100.0%);")
    end

    it "reads assignments, their users and the staff colours in the same number of queries for any number of events" do
      mate = create(:user, :staff)
      StaffSpace.find_by!(user: staff, space: space).update_column(:color, "#111111")
      create(:staff_space, user: mate, space: space).update_column(:color, "#222222")
      add_duo_events = lambda do |count, from|
        count.times do |i|
          ev = create(:event, space: space, title: "Duo #{from + i}", start_time: Time.zone.local(2027, 3, 13, 8 + from + i), end_time: Time.zone.local(2027, 3, 13, 9 + from + i))
          [staff, mate].each { |u| EventAssignment.create!(event: ev, user: u) }
        end
      end

      add_duo_events.call(2, 0)
      few = selects_on("event_assignments", "staff_spaces") { get feed, params: window }.size
      add_duo_events.call(3, 2)
      many = selects_on("event_assignments", "staff_spaces") { get feed, params: window }.size

      expect(response.parsed_body.size).to eq(5)
      expect(response.parsed_body.map { |e| e.dig("extendedProps", "background") }.uniq)
        .to eq(["linear-gradient(to right, #111111 0.0%, #111111 50.0%, #222222 50.0%, #222222 100.0%);"])
      expect(many).to eq(few)
    end

    it "answers 400 for an unparseable start or end param" do
      create(:event, space: space, start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      [{ start: "garbage" }, { end: "garbage" }, { start: "2027-13-45" }].each do |bad|
        get feed, params: bad
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["error"]).to eq(I18n.t("errors.staff.my_calendar.invalid_date"))
      end
    end

    it "falls back to the raw event when the recurrence rule is malformed (inside the window only)" do
      # the model now refuses an unparseable rule, so store it the way legacy rows exist
      bad = create(:event, space: space, title: "Bad", start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      bad.update_column(:recurrence_rule, "NOT A RULE")
      allow(Rails.error).to receive(:report).and_call_original
      get feed, params: window
      expect(response.parsed_body.map { |e| e["title"] }).to eq(["Bad"])
      # the fallback is reported (event id only), not silent
      expect(Rails.error).to have_received(:report)
        .with(kind_of(StandardError), hash_including(handled: true, context: hash_including(event_id: bad.id))).once
    end
  end

  # rules stored before validation existed must not pin a worker.
  describe "a stored sub-daily recurrence rule" do
    before { create(:staff_space, user: sign_in_as(:staff), space: space) }

    def stored_event(rule, title: "Legacy")
      create(:event, space: space, title: title, start_time: Time.utc(2027, 1, 1, 9), end_time: Time.utc(2027, 1, 1, 9, 5))
        .tap { |e| e.update_column(:recurrence_rule, rule) }
    end

    # Counts the candidate occurrences the rule generates, so the bound is on work done, not on time.
    def rule_steps
      steps = 0
      allow_any_instance_of(RRule::Frequency).to receive(:advance).and_wrap_original do |original, *args|
        steps += 1
        original.call(*args)
      end
      yield
      steps
    end

    # No stored rule is finer than daily (the validator refuses them), so the series refuses one without
    # stepping through it; the failure is reported with the event id and the event is shown once.
    def expect_refused_without_stepping(rule)
      event = stored_event(rule)
      allow(Rails.error).to receive(:report).and_call_original
      steps = rule_steps { get feed, params: { start: "2027-01-01T00:00:00Z", end: "2027-04-11T00:00:00Z" } }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |e| e["id"] }).to eq(["event-#{event.id}"])
      expect(Rails.error).to have_received(:report)
        .with(kind_of(RecurringSeries::UnsupportedRule), hash_including(handled: true, context: hash_including(event_id: event.id)))
      expect(steps).to eq(0) # refused before the repeat library is touched (unbounded: 144,000 candidates for MINUTELY)
    end

    it "is refused without stepping through it (MINUTELY over 100 days)" do
      expect_refused_without_stepping("DTSTART:20270101T090000Z\nRRULE:FREQ=MINUTELY")
    end

    it "refuses SECONDLY too" do
      expect_refused_without_stepping("FREQ=SECONDLY")
    end

    it "still caps a daily rule per event" do
      stub_const("Api::V1::ShiftEventSerializer::MAX_OCCURRENCES_PER_EVENT", 5)
      stored_event("FREQ=DAILY")
      steps = rule_steps { get feed, params: { start: "2027-01-01T00:00:00Z", end: "2027-04-11T00:00:00Z" } }
      expect(response.parsed_body.size).to eq(5)
      expect(steps).to be <= 10 # the walk stops after the sixth day, not at the end of the 100 days
    end

    it "leaves a normal rule with fewer occurrences than the cap untouched" do
      create(:event, space: space, title: "Daily", recurrence_rule: "RRULE:FREQ=DAILY;COUNT=3", start_time: Time.utc(2027, 3, 8, 14), end_time: Time.utc(2027, 3, 8, 15))
      get feed, params: window
      expect(response.parsed_body.map { |e| e["start"] }.size).to eq(3)
    end
  end
end
