# frozen_string_literal: true

require "rails_helper"

# Characterization spec for Admin::CalendarController (GET /admin/calendar/…).
# All endpoints bounce non-admins (AdminAreaController#ensure_admin) and use
# `Space ID is required` 400s when params[:id] is missing.
#
# Notes pinned here:
#   - unavailabilities_json / utc_unavailabilities_json group per staff user
#     with color from StaffSpace; each unavailability entry has the
#     "🚫 <name> - <title>" title, className "unavailability" etc.
#   - the :in_time_zone("America/Toronto") round-trip of the UTC variant maps
#     back to the values they were written with (creation is UTC-normalized,
#     readback is evaluated as UTC then re-zoned)
#   - update_color only flashes (no render/redirect) → the response collapses
#     to 204 No Content even when data changed (wart)
#   - ics_to_json has a route but NO action → 404 (wart)

RSpec.describe "Admin calendar contract", type: :request do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
  end

  let(:space) { create(:space) }
  let(:staff) { create(:user, :staff, booking_approval: true) }
  let(:admin) { create(:user, :admin, booking_approval: true) }

  def log_in!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
    follow_redirect!
  end

  it "bounces regular users everywhere (redirect to /)" do
    log_in!(create(:user, :regular_user, booking_approval: true))
    get admin_calendar_index_path
    expect(response).to redirect_to(root_path)

    get unavailabilities_json_admin_calendar_index_path(id: space.id)
    expect(response).to redirect_to(root_path)
  end

  it "flags views when the admin has no staffed spaces (flash)" do
    create(:space) # one exists, but nobody is staffed on it
    log_in!(admin)
    get admin_calendar_index_path
    expect(response.status).to eq(200)
    expect(flash[:alert]).to eq("You are not assigned to any spaces.")
  end

  # WART: index falls back with `@user.space_id || Space.first.id` — if the
  # DB contains NO spaces at all, Space.first is nil and `.id` raises — 500.
  it "WART: index 500s when no spaces exist at all" do
    log_in!(admin) # nothing else creates a space in this example
    get admin_calendar_index_path
    expect(response.status).to eq(500) # NoMethodError on Space.first.id
  end

  # NOTE: the :id segment is REQUIRED by the route, so the controller's
  # `params[:id].blank? → 400` branch is unreachable under the route shim;
  # `/…_json/0` (unknown space) returns 200 with an empty list. Pinned that.
  it "admin.?json for an unknown space id → 200 with empty payload" do
    log_in!(admin)
    get unavailabilities_json_admin_calendar_index_path(id: 0)
    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq([])

    get utc_unavailabilities_json_admin_calendar_index_path(id: 0)
    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq([])

    get imported_calendars_json_admin_calendar_index_path(id: 0)
    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq([])
  end

  describe "GET unavailabilities_json" do
    before do
      log_in!(admin)
    end

    def staff_space!(color = "#3788d8")
      StaffSpace.create!(user: staff, space: space, color: color)
    end

    def unavailability
      StaffUnavailability.create!(
        user: staff, title: "Doctor",
        description: "Away at hospital",
        start_time: Time.zone.parse("2027-05-05 09:00"),
        end_time: Time.zone.parse("2027-05-05 11:00")
      )
    end

    # WART: StaffSpace#before_create :create_color OVERWRITES any color
    # passed to create! — generate_color picks the first global palette
    # entry not yet taken in the space, so a brand-new StaffSpace always
    # gets "#e6194b" (palette x 22 colors) regardless of what we assign.
    it "shares UNAVAILABILITY entries under the staff + literal wall re-zoned" do
      staff_space!
      unavailability

      get unavailabilities_json_admin_calendar_index_path(id: space.id)
      expect(response.status).to eq(200)
      body = response.parsed_body

      expect(body.size).to eq(1)
      staff_entry = body.first
      expect(staff_entry.keys)
        .to eq(%w[id name color unavailabilities])
      expect(staff_entry["id"]).to eq(staff.id)
      # not the "#3788d8" the helper assigned — see WART note above
      expect(staff_entry["color"]).to eq("#e6194b")

      event = staff_entry["unavailabilities"].first
      expect(event["title"]).to eq("🚫 #{staff.name} - Doctor")
      expect(event["start"]).to eq("2027-05-05T09:00:00")
      expect(event["end"]).to eq("2027-05-05T11:00:00")
      expect(event["allDay"]).to be(false)
      expect(event).not_to include("rrule")
      expect(event["className"]).to eq("unavailability")
      expect(event["extendedProps"]).to eq(
        "name" => staff.name, "description" => "Away at hospital"
      )
    end

    it "allDay goes true when end == start + 1 day" do
      staff_space!
      StaffUnavailability.create!(
        user: staff,
        start_time: Time.zone.parse("2027-05-05 09:00"),
        end_time: Time.zone.parse("2027-05-06 09:00")
      )
      get unavailabilities_json_admin_calendar_index_path(id: space.id)
      expect(response.parsed_body.first["unavailabilities"].first["allDay"])
        .to be(true)
    end

    it "UTC variant: keeps full iso8601 (require zone/millis) + conflict copy" do
      staff_space!
      entry = StaffUnavailability.create!(
        user: staff, title: "Conference",
        start_time: Time.zone.parse("2027-05-05 09:00"),
        end_time: Time.zone.parse("2027-05-05 11:00")
      )
      get utc_unavailabilities_json_admin_calendar_index_path(id: space.id)
      event = response.parsed_body.first["unavailabilities"].first
      # raw active-record attribute time format (no custom strftime)
      expect(event["start"]).to eq(entry.start_time.iso8601(3))
      expect(event["end"]).to eq(entry.end_time.iso8601(3))
    end

    it "returns staff without unavailabilities with empty lists" do
      staff_space!
      get unavailabilities_json_admin_calendar_index_path(id: space.id)
      body = response.parsed_body
      expect(body.first["unavailabilities"]).to eq([])
      expect(body.first["name"]).to eq(staff.name)
    end

    # N+1 pinned: see defects.md D-PERF14
    it "orders staff by name descending", skip_bullet: true do
      s1 = StaffSpace.create!(space: space, color: "#111111",
                              user: create(:user, :staff, name: "Zeta"))
      s2 = StaffSpace.create!(space: space, color: "#222222",
                              user: create(:user, :staff, name: "Alpha"))
      get utc_unavailabilities_json_admin_calendar_index_path(id: space.id)
      expect(response.parsed_body.map { |e| e["name"] })
        .to eq(["Zeta", "Alpha"])
    end
  end

  describe "GET imported_calendars_json" do
    it "renders parse results of the space's ICS calendars (empty = [] here)" do
      log_in!(admin)
      get imported_calendars_json_admin_calendar_index_path(id: space.id)
      expect(response.status).to eq(200)
      expect(response.parsed_body).to eq([])
    end
  end

  # WART: the route exists, the controller action does not — any request
  # raises AbstractController::ActionNotFound → 404.
  it "ics_to_json 404s (route without controller action)" do
    log_in!(admin)
    get ics_to_json_admin_calendar_index_path
    expect(response.status).to eq(404)
  end

  # WART: update_color only ever assigns flash — no render, no redirect,
  # and no template exists for the action — so both the success path (which
  # also mutated data) and the failure path fall through to an empty
  # render-less response that surfaces as 204 No Content. Verified live.
  it "update_color returns 204 on success AND failure; color persists" do
    log_in!(admin)
    admin.update_column(:space_id, space.id)
    row = StaffSpace.create!(user: admin, space: space, color: "#3788d8")

    post update_color_admin_calendar_index_path,
         params: { user_id: admin.id, color: "#ff0000" }
    expect(response.status).to eq(204)
    expect(row.reload.color).to eq("#ff0000") # data changed via 204 (wart)

    post update_color_admin_calendar_index_path, params: {}
    expect(response.status).to eq(204) # alert branch is ALSO flash-only
  end
end
