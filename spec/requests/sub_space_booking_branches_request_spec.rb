# frozen_string_literal: true

require "rails_helper"

# Combinations of the booking controller's create, update and index conditions that the other booking
# specs do not take one by one: each half of the series check, admins and the block and limit checks,
# and the supervisor list of the access form.
RSpec.describe "Sub space booking branches", :booking_clock, type: :request do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    create(:booking_status, :rejected)
  end

  let(:space) { create(:space) }
  let(:subspace) { create(:sub_space, space: space) }
  let(:user) { create(:user, :regular_user, booking_approval: true) }
  let(:admin) { create(:user, :admin, booking_approval: true) }

  def log_in!(account)
    post login_authentication_path,
         params: { username_email: account.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  def blocking_row(target, start_wall, end_wall)
    row = create(:sub_space_booking, sub_space: target, user: admin, name: "Block",
                                     start_time: Time.zone.parse(start_wall),
                                     end_time: Time.zone.parse(end_wall), blocking: true)
    row.change_status!(@approved_status)
    row
  end

  def booking_of(owner, target = subspace, day: "2027-04-03", from: "10:00", to: "11:00")
    booking = create(:sub_space_booking, sub_space: target, user: owner,
                                         start_time: Time.zone.parse("#{day} #{from}"),
                                         end_time: Time.zone.parse("#{day} #{to}"))
    booking.change_status!(@pending_status)
    booking
  end

  def patch_booking(booking, as: :json, **fields)
    patch sub_space_booking_update_path(sub_space_booking_id: booking.id), as: as,
          params: { sub_space_booking: { name: "Moved", description: "D" }.merge(fields) }
  end

  describe "POST create series checks" do
    before { log_in!(user) }

    def post_series(**series)
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-02-03 10:00", end_time: "2027-02-03 11:00",
             name: "Series", description: "D", recurring: true
           }.merge(series) }
    end

    let(:invalid) { ["Recurring #{I18n.t("errors.bookings.recurring_invalid")}"] }

    it "refuses a series with a frequency but no end date" do
      post_series(recurring_frequency: "weekly")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => invalid)
      expect(SubSpaceBooking.exists?(name: "Series")).to be(false)
    end

    it "refuses a series with a frequency and an end date that is not a date" do
      post_series(recurring_frequency: "weekly", recurring_end: "not-a-date")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => invalid)
      expect(SubSpaceBooking.exists?(name: "Series")).to be(false)
    end

    it "refuses a series with an end date but no frequency" do
      post_series(recurring_end: "2027-02-17")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => invalid)
      expect(SubSpaceBooking.exists?(name: "Series")).to be(false)
    end
  end

  describe "POST create by an admin" do
    before { log_in!(admin) }

    it "refuses an admin's plain booking over a block" do
      blocking_row(subspace, "2027-03-03 09:00", "2027-03-03 12:00")
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-03-03 10:00", end_time: "2027-03-03 11:00",
             name: "AdminPlain", description: "D"
           } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."])
      expect(SubSpaceBooking.exists?(name: "AdminPlain")).to be(false)
    end

    it "lets an admin book past the room's maximum duration and weekly hours together" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 1, maximum_booking_hours_per_week: 1)
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: capped.id, start_time: "2027-03-03 10:00", end_time: "2027-03-03 13:00",
             name: "AdminLong", description: "D"
           } }
      expect(response).to have_http_status(:no_content)
      booking = SubSpaceBooking.find_by!(name: "AdminLong")
      expect(booking).to be_approved
      expect(booking.approved_by_id).to eq(admin.id)
    end
  end

  describe "PATCH update by an admin" do
    before { log_in!(admin) }

    it "refuses an admin moving a booking onto a block" do
      booking = booking_of(user)
      blocking_row(subspace, "2027-04-03 12:00", "2027-04-03 14:00")
      patch_booking(booking, start_time: "2027-04-03 12:30", end_time: "2027-04-03 13:30")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."])
      expect(booking.reload.name).not_to eq("Moved")
    end

    # Unlike create, update checks the blocks for a blocking booking too.
    it "refuses an admin moving a block onto another block" do
      own_block = blocking_row(subspace, "2027-04-03 08:00", "2027-04-03 09:00")
      blocking_row(subspace, "2027-04-03 12:00", "2027-04-03 14:00")
      patch_booking(own_block, start_time: "2027-04-03 12:30", end_time: "2027-04-03 13:30", blocking: true)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."])
      expect(own_block.reload.name).to eq("Block")
    end

    it "lets an admin move a booking past the room's weekly hours" do
      capped = create(:sub_space, space: space, maximum_booking_hours_per_week: 1)
      booking = booking_of(user, capped)
      patch_booking(booking, start_time: "2027-04-03 10:00", end_time: "2027-04-03 13:00")
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "ok")
      expect(booking.reload.end_time - booking.start_time).to eq(3.hours)
    end
  end

  describe "PATCH update by the owner" do
    before { log_in!(user) }

    it "checks the weekly hours of the room the booking moves to" do
      capped = create(:sub_space, space: space, maximum_booking_hours_per_week: 1)
      booking = booking_of(user)
      booking.update_column(:sub_space_id, capped.id)
      patch_booking(booking, start_time: "2027-04-03 10:00", end_time: "2027-04-03 12:00")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq(
        "errors" => ["DurationWeek You cannot book #{capped.name} for more than 1 hours per week."]
      )
    end

    it "answers a failed validation as JSON with the record's errors" do
      booking = booking_of(user)
      patch_booking(booking, start_time: "2027-04-03 12:00", end_time: "2027-04-03 10:00")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.keys).to eq(["errors"])
      expect(response.parsed_body["errors"]).to include(a_string_starting_with("End time"))
      expect(booking.reload.name).not_to eq("Moved")
    end
  end

  describe "GET index supervisors" do
    let(:applicant) { create(:user, :regular_user, booking_approval: false) }

    it "lists each space manager once, sorted by name ignoring case, on the access request form" do
      bob = create(:user, :admin, name: "bob Manager")
      alice = create(:user, :admin, name: "Alice Manager")
      other_space = create(:space)
      SpaceManagerJoin.create!(user: bob, space: space)
      SpaceManagerJoin.create!(user: bob, space: other_space)
      SpaceManagerJoin.create!(user: alice, space: space)

      log_in!(applicant)
      get sub_space_booking_index_path
      expect(response).to have_http_status(:ok)
      options = Capybara.string(response.body).all("select#supervisor option", visible: :all)
      expect(options.map { |option| [option.text, option[:value]] })
        .to eq([["Alice Manager", alice.id.to_s], ["bob Manager", bob.id.to_s]])
    end
  end
end
