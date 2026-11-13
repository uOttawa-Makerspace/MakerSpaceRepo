# frozen_string_literal: true

require "rails_helper"

# GET /admin/calendar/staff_conflicts: the event dialog's staff ranking. The proposed event's occurrences over four
# weeks (RecurringSeries) are checked against each staff member's stored and external-calendar unavailabilities, on
# the server, in Toronto time whatever the zone of the browser that asks.
RSpec.describe "Admin calendar staff conflicts", type: :request do
  include SpacesSpecHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { RecurrenceRule::ZONE }
  let(:space) { create(:space) }
  let(:ada) { create(:user, :staff, name: "Ada") }
  let(:bob) { create(:user, :staff, name: "Bob") }

  around { |example| travel_to(Time.utc(2026, 1, 1, 12)) { example.run } }

  before do
    StaffSpace.create!(user: ada, space: space, color: "#ff0000")
    StaffSpace.create!(user: bob, space: space, color: "#00ff00")
    # Ada works Mondays 9:00-14:20 from a rule written in winter; Bob is free.
    create(:staff_unavailability, user: ada, start_time: zone.local(2026, 1, 5, 9), end_time: zone.local(2026, 1, 5, 14, 20),
                                  recurrence_rule: "DTSTART:20260105T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO")
  end

  # The proposal as the dialog sends it: the instants of the Toronto times in the form, and the rule as stored.
  def conflicts(start, finish, rule = "")
    get admin_calendar_staff_conflicts_path,
        params: { space_id: space.id, start: zone.parse(start).utc.iso8601, end: zone.parse(finish).utc.iso8601, recurrence_rule: rule }
    response.parsed_body
  end

  def ada_starts(*) = conflicts(*).find { |member| member["name"] == "Ada" }["unavailableStarts"]

  describe "as an admin" do
    before { sign_in_as(:admin) }

    {
      "flags 9:30 on 2026-03-30" => ["2026-03-30T09:30", "2026-03-30T10:00", true],
      "flags 14:00 on 2026-03-30" => ["2026-03-30T14:00", "2026-03-30T14:30", true],
      "does not flag 14:20 on 2026-03-30 (the shift is over)" => ["2026-03-30T14:20", "2026-03-30T15:00", false],
      "does not flag 8:00-9:00 on 2026-03-30 (it only touches the shift)" => ["2026-03-30T08:00", "2026-03-30T09:00", false],
      "flags 9:30 on 2026-03-09, the first Monday after the clocks go forward" => ["2026-03-09T09:30", "2026-03-09T10:00", true],
      "flags 9:30 on 2026-11-02, after the clocks go back" => ["2026-11-02T09:30", "2026-11-02T10:00", true],
      "does not flag 15:00 on 2026-11-02" => ["2026-11-02T15:00", "2026-11-02T16:00", false],
      "does not flag a Sunday, the day of the clock change" => ["2026-03-08T09:30", "2026-03-08T10:00", false]
    }.each do |label, (start, finish, flagged)|
      it label do
        expect(ada_starts(start, finish).any?).to be(flagged)
      end
    end

    it "lists available staff first, then the unavailable ones, each by name, with their colours" do
      expect(conflicts("2026-03-30T09:30", "2026-03-30T10:00")).to eq([
        { "id" => bob.id, "name" => "Bob", "color" => "#00ff00", "unavailableStarts" => [] },
        { "id" => ada.id, "name" => "Ada", "color" => "#ff0000", "unavailableStarts" => ["2026-03-30T13:30:00Z"] }
      ])
    end

    it "checks every occurrence of a repeating event over four weeks, across the clock change" do
      rule = "DTSTART;TZID=America/Toronto:20260302T140000\nRRULE:FREQ=WEEKLY;BYDAY=MO"
      # 14:00 in Toronto: 19:00Z before the change, 18:00Z after it
      expect(ada_starts("2026-03-02T14:00", "2026-03-02T14:30", rule))
        .to eq(%w[2026-03-02T19:00:00Z 2026-03-09T18:00:00Z 2026-03-16T18:00:00Z 2026-03-23T18:00:00Z])
    end

    it "flags the occurrence on the night the clocks go back in the repeated hour" do
      create(:staff_unavailability, user: bob, start_time: zone.local(2026, 11, 1, 1, 0), end_time: zone.local(2026, 11, 1, 1, 45))
      bob_starts = conflicts("2026-11-01T01:30", "2026-11-01T02:00").find { |member| member["name"] == "Bob" }["unavailableStarts"]
      expect(bob_starts).to eq(["2026-11-01T05:30:00Z"])
    end

    it "flags a staff member busy on their external calendar" do
      url = "https://calendar.example.test/bob.ics"
      StaffExternalUnavailability.create!(user: bob, ics_url: url)
      stub_ics(url, body: ics_document(uid: "dentist", summary: "Dentist", start: zone.local(2026, 3, 31, 9), end: zone.local(2026, 3, 31, 10)))
      bob_starts = conflicts("2026-03-31T09:30", "2026-03-31T10:30").find { |member| member["name"] == "Bob" }["unavailableStarts"]
      expect(bob_starts).to eq(["2026-03-31T13:30:00Z"])
    end

    it "answers 422 with the reason for a rule that cannot be stored" do
      get admin_calendar_staff_conflicts_path,
          params: { space_id: space.id, start: "2026-03-30T13:30:00Z", end: "2026-03-30T14:00:00Z", recurrence_rule: "RRULE:FREQ=HOURLY" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to be_present
    end

    it "answers 400 with the reason for times it cannot read" do
      get admin_calendar_staff_conflicts_path, params: { space_id: space.id, start: "2026-03-30T14:00:00Z", end: "2026-03-30T13:00:00Z" }
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => I18n.t("errors.calendar.window_invalid"))
    end

    it "answers an empty list for an unknown space" do
      get admin_calendar_staff_conflicts_path, params: { space_id: 0, start: "2026-03-30T13:30:00Z", end: "2026-03-30T14:00:00Z" }
      expect(response.parsed_body).to eq([])
    end
  end

  describe "authorization" do
    let(:call) { -> { get admin_calendar_staff_conflicts_path, params: { space_id: space.id, start: "2026-03-30T13:30:00Z", end: "2026-03-30T14:00:00Z" } } }

    it "sends a guest to sign in" do
      call.call
      expect_admin_area_bounce(guest: true)
    end

    %i[regular staff].each do |role|
      it "sends a #{role} user to the home page" do
        sign_in_as(role)
        call.call
        expect_admin_area_bounce(guest: false)
      end
    end
  end
end
