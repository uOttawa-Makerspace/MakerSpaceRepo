# frozen_string_literal: true

require "rails_helper"

# FORENSIC contract spec for GET /sub_space_booking/bookings?room=<sub_space_id>
# (SubSpaceBookingController#bookings) — the JSON payload consumed by the
# FullCalendar feed on the booking page. This file pins the *literal wire
# format* so any refactor (or Rails upgrade) must keep the exact keys,
# formatting and ordering that the JS currently depends on.
#
# Wire contract pinned here:
#   - array of event objects, keys in construction order: id, title, start,
#     end, color
#   - id: "booking_<booking.id>_<booking.sub_space_id>"
#   - start/end: the stored timestamp wall, evaluated as UTC on readback and
#     re-formatted in the app zone ("Eastern Time (US & Canada)") as
#     iso8601 with 3 millisecond digits: "YYYY-MM-DDTHH:MM:00.000-04:00"
#     (April → EDT -04:00). The value the user typed into the form is NOT
#     preserved through create → feed (controller create shifts it +4/+5).
#   - title: "#{name} - #{description}" for public/own/admin-visible events,
#     + " (Pending)" suffix for PENDING status,
#     + " - #{user.name}" suffix ONLY for admins viewing other users' pending
#     bookings, "Space Booked" for private other-user events, "Space Blocked"
#     for blocking bookings (admins included unless they own it)
#   - color: one of the SubSpaceBooking::COLOR_LEGEND hexes
#   - only APPROVED + PENDING rows appear (DECLINED filtered out)

RSpec.describe "Bookings feed JSON contract", type: :request do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
  end

  let(:space) { create(:space) }
  let(:subspace) { create(:sub_space, space: space) }
  let(:viewer) { create(:user, :regular_user, booking_approval: true) }
  let(:admin) { create(:user, :admin, booking_approval: true) }
  let(:owner) { create(:user, :regular_user, booking_approval: true) }

  # Booking factory hooks a Pending status row after create; override it.
  def set_booking_status!(booking, status_row)
    booking.sub_space_booking_status
           .update!(booking_status_id: status_row.id)
    booking
  end

  # Real login (sessions_controller#authenticate): null_store cache in the
  # test env means the login rate limit never trips in tests.
  def log_in!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
    follow_redirect!
  end

  def approved_booking(**attrs)
    set_booking_status!(
      create(:sub_space_booking, { sub_space: subspace, user: owner,
             start_time: DateTime.parse("2027-04-01 10:00"),
             end_time: DateTime.parse("2027-04-01 11:00") }.merge(attrs)),
      @approved_status
    )
  end

  def fetch(room: subspace.id, user: viewer)
    log_in!(user)
    get bookings_sub_space_booking_index_path, params: { room: room }
    expect(response).to have_http_status(:ok)
    response.body
  end

  it "pins the literal body for a public confirmed booking (keys + order + 3ms EDT timestamps)" do
    approved_booking(name: "Kappa", description: "Session",
                     public: true,
                     start_time: DateTime.parse("2027-04-01 10:00"),
                     end_time: DateTime.parse("2027-04-01 11:00"))
    booking = SubSpaceBooking.find_by!(name: "Kappa")

    # offset-0 DateTime stores the literal wall (10:00/11:00); feed shows it
    # UTC-evaluated + reformatted in Eastern (-04:00 for April EDT).
    expect(fetch).to eq(
      [
        {
          id: "booking_#{booking.id}_#{subspace.id}",
          title: "Kappa - Session",
          start: "2027-04-01T06:00:00.000-04:00",
          end: "2027-04-01T07:00:00.000-04:00",
          color: "#497979"
        }
      ].to_json
    )
  end

  it "appends (Pending), keeps milliseconds .000 and lists keys first" do
    booking = approved_booking(name: "P", description: "D", public: true)
    booking.sub_space_booking_status.update!(booking_status_id: @pending_status.id)

    body = JSON.parse(fetch)
    expect(body.size).to eq(1)
    expect(body.first.keys).to eq(%w[id title start end color])
    expect(body.first["title"]).to eq("P - D (Pending)")
    expect(body.first["start"]).to end_with(".000-04:00")
    expect(body.first["color"]).to eq("#FFA500")
  end

  it "hides other users' private bookings behind 'Space Booked'" do
    approved_booking(name: "S", description: "D", public: false)
    expect(JSON.parse(fetch).first["title"]).to eq("Space Booked")
  end

  it "shows 'Space Blocked' for blocking bookings (admins included)" do
    approved_booking(name: "B", description: "D", public: false, blocking: true)
    expect(JSON.parse(fetch).first["title"]).to eq("Space Blocked")
    expect(JSON.parse(fetch(user: admin)).first)
      .to include("title" => "Space Blocked", "color" => "#ABABABFF")
  end

  it "row order: ASC by id for rows fetched with find_each (NOT start order)" do
    b1 = approved_booking(name: "First", description: "Brief",
                          start_time: DateTime.parse("2027-04-02 10:00"),
                          end_time: DateTime.parse("2027-04-02 11:00"))
    b2 = approved_booking(name: "Second", description: "Brief",
                          start_time: DateTime.parse("2027-04-01 09:00"),
                          end_time: DateTime.parse("2027-04-01 10:00"))
    body = JSON.parse(fetch)
    expect(body.map { |e| e["start"] })
      .to eq(["2027-04-02T06:00:00.000-04:00", "2027-04-01T05:00:00.000-04:00"])
    # WART: no ORDER clause on find_each — the feed comes back in
    # insertion (id) order, not sorted by start_time.
    expect(body.map { |e| e["id"] })
      .to eq(["booking_#{b1.id}_#{subspace.id}", "booking_#{b2.id}_#{subspace.id}"])
  end

  it "includes the admin name suffix for admin pending views" do
    booking = approved_booking(name: "O2", description: "D", public: false)
    booking.sub_space_booking_status.update!(booking_status_id: @pending_status.id)
    expect(JSON.parse(fetch(user: admin)).first["title"])
      .to eq("O2 - D (Pending) - #{owner.name}")
  end

  it "excludes declined bookings" do
    booking = approved_booking(name: "Gone", description: "D", public: true)
    booking.sub_space_booking_status.update!(booking_status_id: @declined_status.id)
    expect(fetch).to eq("[]")
  end

  it "returns an empty array without a room/without bookings" do
    expect(fetch(room: nil)).to eq("[]")
  end
end
