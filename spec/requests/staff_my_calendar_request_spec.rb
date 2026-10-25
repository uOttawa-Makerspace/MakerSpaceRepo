# frozen_string_literal: true

require "rails_helper"

# Staff::MyCalendarController (index page + JSON feed). The feed is built from
# Event rows (not Shift, which no controller uses). The app zone is Eastern;
# recurring events are expanded with IceCube from the event's own start_time, so
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

    # WART(D-SP16): index calls @spaces.first.id: staff with no StaffSpace (and no space_id) get a 500.
    it "500s for staff assigned to no space" do
      sign_in_as(:staff)
      get staff_my_calendar_index_path
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "json feed" do
    around { |ex| travel_to(Time.zone.local(2027, 3, 12, 12)) { ex.run } }

    let!(:staff) { sign_in_as(:staff) }

    it "does not scope the feed to the staff member's spaces: any staff can read any space" do
      other_space = create(:space)
      create(:event, space: other_space, title: "Elsewhere", start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
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
      create(:event, space: space, title: "Weekly", recurrence_rule: "FREQ=WEEKLY;BYDAY=SU;COUNT=4",
                     start_time: Time.zone.local(2027, 3, 7, 10), end_time: Time.zone.local(2027, 3, 7, 11))
      get feed, params: { start: "2027-03-01T00:00:00-05:00", end: "2027-04-01T00:00:00-04:00" }
      starts = response.parsed_body.map { |e| e["start"] }
      expect(starts).to eq(%w[2027-03-07T10:00:00-05:00 2027-03-14T10:00:00-04:00 2027-03-21T10:00:00-04:00 2027-03-28T10:00:00-04:00])
      expect(response.parsed_body.map { |e| e["id"] }.uniq.size).to eq(4)
      expect(response.parsed_body.first["id"]).to match(/\Aevent-\d+-\d+\z/)
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

    # N+1 pinned: see defects D-PERF-SP01 (format_event reads event_assignments per event; Bullet raises in CI mode)
    it "defaults the window to now-3 months .. now+3 months", skip_bullet: true do
      create(:event, space: space, title: "Soon", start_time: Time.zone.local(2027, 4, 1, 9), end_time: Time.zone.local(2027, 4, 1, 10))
      create(:event, space: space, title: "Far", start_time: Time.zone.local(2027, 9, 1, 9), end_time: Time.zone.local(2027, 9, 1, 10))
      get feed
      expect(response.parsed_body.map { |e| e["title"] }).to eq(["Soon"])
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

    # N+1 pinned: see defects D-PERF-SP01 (assignment.user and StaffSpace.find_by per assignment)
    it "colours assigned events by StaffSpace colour and flags the current user", skip_bullet: true do
      mate = create(:user, :staff)
      create(:staff_space, user: staff, space: space).update_column(:color, "#111111")
      create(:staff_space, user: mate, space: space).update_column(:color, "#222222")
      ev = create(:event, space: space, title: "Duo", start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      [staff, mate].each { |u| EventAssignment.create!(event: ev, user: u) }
      get feed, params: window
      props = response.parsed_body.first["extendedProps"]
      expect(props["hasCurrentUser"]).to be(true)
      expect(props["background"]).to eq("linear-gradient(to right, #111111 0.0%, #111111 50.0%, #222222 50.0%, #222222 100.0%);")
    end

    # WART(D-SP17): an unparseable start/end param parses to nil; with any single event in the space the nil comparison 500s (empty space: 200 []).
    it "500s for an unparseable start param once the space has a single event" do
      get feed, params: { start: "garbage" }
      expect(response.parsed_body).to eq([])
      create(:event, space: space, start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      get feed, params: { start: "garbage" }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "falls back to the raw event when the recurrence rule is malformed (inside the window only)" do
      create(:event, space: space, title: "Bad", recurrence_rule: "NOT A RULE", start_time: Time.zone.local(2027, 3, 13, 9), end_time: Time.zone.local(2027, 3, 13, 10))
      get feed, params: window
      expect(response.parsed_body.map { |e| e["title"] }).to eq(["Bad"])
    end
  end
end
