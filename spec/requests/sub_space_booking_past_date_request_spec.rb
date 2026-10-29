# frozen_string_literal: true

require "rails_helper"

# D-B18, past-date half (user decision 2026-10-25): bookings may not be created
# or moved to start in the past, for every role, admins and admin blocks
# included. An edit that leaves an already-past booking's times alone stays
# allowed, approving or declining a past pending booking keeps working, and a
# recurring series skips its past occurrences.
#
# The clock is BookingClock::NOW: Tuesday 2026-12-01 12:00 Toronto (EST).
# There are no /api/v1 booking endpoints; bookings are made only here.
RSpec.describe "Sub space booking past-date rule", :booking_clock, type: :request do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
    ActionMailer::Base.deliveries.clear
  end

  let(:past_error) { "Start time cannot be in the past. Pick a start time from now on." }
  let(:space) { create(:space) }
  let(:subspace) { create(:sub_space, space: space) }
  let(:user) { create(:user, :regular_user, booking_approval: true) }
  let(:staff) { create(:user, :staff, booking_approval: true) }
  let(:admin) { create(:user, :admin, booking_approval: true) }

  def log_in!(account)
    post login_authentication_path,
         params: { username_email: account.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
    follow_redirect!
  end

  def create_booking(start_time:, end_time:, name: "Fresh", **extra)
    post sub_space_booking_index_path, as: :json,
         params: { sub_space_booking: {
           sub_space_id: subspace.id, start_time: start_time, end_time: end_time,
           name: name, description: "Desc"
         }.merge(extra) }
  end

  def booking_of(owner, start_time:, end_time:, status: @pending_status)
    booking = create(:sub_space_booking, sub_space: subspace, user: owner, name: "Existing",
                                         start_time: Time.zone.parse(start_time),
                                         end_time: Time.zone.parse(end_time))
    booking.sub_space_booking_status.update!(booking_status_id: status.id)
    booking
  end

  def status_name(booking)
    booking.reload.sub_space_booking_status.booking_status.name
  end

  describe "POST create" do
    { user: :user, staff: :staff, admin: :admin }.each do |role, account|
      it "refuses a #{role} booking that starts in the past (422, nothing saved, no mail)" do
        log_in!(public_send(account))
        create_booking(start_time: "2026-11-30 10:00", end_time: "2026-11-30 11:00")
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq("errors" => [past_error])
        expect(SubSpaceBooking.where(name: "Fresh")).to be_empty
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    it "refuses a booking that started earlier today and is still running" do
      log_in!(user)
      create_booking(start_time: "2026-12-01 11:00", end_time: "2026-12-01 13:00")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [past_error])
    end

    it "accepts a booking that starts this minute or later" do
      log_in!(user)
      create_booking(start_time: "2026-12-01 12:00", end_time: "2026-12-01 13:00", name: "Now")
      expect(response).to have_http_status(:no_content)
      create_booking(start_time: "2026-12-02 10:00", end_time: "2026-12-02 11:00", name: "Tomorrow")
      expect(response).to have_http_status(:no_content)
      expect(SubSpaceBooking.where(name: %w[Now Tomorrow]).count).to eq(2)
    end

    # Admin blocks over existing bookings are intended (D-B04/B18), but
    # "admins included" covers blocks: a past-dated block is refused too.
    it "refuses a past-dated admin block" do
      log_in!(admin)
      create_booking(start_time: "2026-11-30 10:00", end_time: "2026-11-30 11:00",
                     name: "PastBlock", blocking: true)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [past_error])
      expect(SubSpaceBooking.where(name: "PastBlock")).to be_empty
    end

    it "uses the French message under the fr locale" do
      log_in!(user)
      post sub_space_booking_index_path(locale: "fr"), as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2026-11-30 10:00",
             end_time: "2026-11-30 11:00", name: "Fresh", description: "Desc"
           } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to eq(
        ["Start time ne peut pas être dans le passé. Choisissez une heure de début à partir de maintenant."]
      )
    end
  end

  describe "POST create recurring" do
    def post_series(start_on:, end_on:, name: "Series", room: subspace)
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: room.id, start_time: "#{start_on} 10:00",
             end_time: "#{start_on} 11:00", name: name, description: "D",
             recurring: true, recurring_frequency: "weekly", recurring_end: end_on
           } }
    end

    def walls_of(name)
      SubSpaceBooking.where(name: name).order(:start_time)
                     .map { |b| b.start_time.in_time_zone.strftime("%Y-%m-%d %H:%M") }
    end

    # 11-17, 11-24 and 12-01 10:00 are past at 12:00 on 12-01; 12-08 and
    # 12-15 are not (the series overshoot of D-B29 still applies).
    it "creates only the future occurrences of a series that straddles now, in one group" do
      log_in!(user)
      post_series(start_on: "2026-11-17", end_on: "2026-12-15")
      expect(response).to have_http_status(:no_content)
      expect(walls_of("Series")).to eq(["2026-12-08 10:00", "2026-12-15 10:00"])
      expect(SubSpaceBooking.where(name: "Series").distinct.pluck(:recurring_booking_id).compact.size).to eq(1)
    end

    it "mails once, for the first occurrence that is booked" do
      managed = create(:space, :with_space_managers)
      room = create(:sub_space, space: managed, approval_required: true, max_automatic_approval_hour: nil)
      log_in!(user)
      post_series(start_on: "2026-11-17", end_on: "2026-12-15", name: "Mailed", room: room)
      expect(walls_of("Mailed")).to eq(["2026-12-08 10:00", "2026-12-15 10:00"])
      expect(ActionMailer::Base.deliveries.map(&:subject)).to eq(["Booking needs approval"])
    end

    it "refuses a series whose occurrences are all in the past (422, nothing saved)" do
      log_in!(admin)
      post_series(start_on: "2026-11-03", end_on: "2026-11-20", name: "AllPast")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [past_error])
      expect(SubSpaceBooking.where(name: "AllPast")).to be_empty
      expect(RecurringBooking.count).to eq(0)
    end
  end

  describe "PATCH update" do
    def update_path_for(booking)
      sub_space_booking_update_path(sub_space_booking_id: booking.id)
    end

    def patch_times(booking, start_time, end_time, name:, as: :json)
      patch update_path_for(booking), as: as, params: {
        sub_space_booking: { start_time: start_time, end_time: end_time, name: name, description: "D" }
      }
    end

    it "refuses moving a future booking into the past (JSON 422 and HTML alert), times unchanged" do
      log_in!(user)
      booking = booking_of(user, start_time: "2026-12-03 10:00", end_time: "2026-12-03 11:00")

      patch_times(booking, "2026-11-30 10:00", "2026-11-30 11:00", name: "Back")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [past_error])

      patch_times(booking, "2026-11-30 10:00", "2026-11-30 11:00", name: "Back", as: :html)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Booking")
      expect(flash[:alert]).to eq(past_error)

      booking.reload
      expect(booking.name).to eq("Existing")
      expect(booking.start_time).to eq(Time.zone.parse("2026-12-03 10:00"))
    end

    it "refuses an admin moving any booking into the past" do
      log_in!(admin)
      booking = booking_of(user, start_time: "2026-12-03 10:00", end_time: "2026-12-03 11:00",
                                 status: @approved_status)
      patch_times(booking, "2026-11-30 10:00", "2026-11-30 11:00", name: "Back")
      expect(response).to have_http_status(:unprocessable_content)
      expect(booking.reload.start_time).to eq(Time.zone.parse("2026-12-03 10:00"))
    end

    it "lets the owner rename a past booking when the times are resubmitted unchanged" do
      log_in!(user)
      booking = booking_of(user, start_time: "2026-11-30 10:00", end_time: "2026-11-30 11:00")
      patch_times(booking, "2026-11-30 10:00", "2026-11-30 11:00", name: "Renamed")
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "ok")
      expect(booking.reload.name).to eq("Renamed")
    end

    it "refuses moving a past booking to another past time" do
      log_in!(user)
      booking = booking_of(user, start_time: "2026-11-30 10:00", end_time: "2026-11-30 11:00")
      patch_times(booking, "2026-11-29 10:00", "2026-11-29 11:00", name: "Shuffled")
      expect(response).to have_http_status(:unprocessable_content)
      expect(booking.reload.name).to eq("Existing")
    end

    it "lets a past booking move to the future" do
      log_in!(user)
      booking = booking_of(user, start_time: "2026-11-30 10:00", end_time: "2026-11-30 11:00")
      patch_times(booking, "2026-12-04 10:00", "2026-12-04 11:00", name: "Rescheduled")
      expect(response).to have_http_status(:ok)
      expect(booking.reload.start_time).to eq(Time.zone.parse("2026-12-04 10:00"))
    end
  end

  # These write only the status and the approval stamp, never the times, so
  # the rule leaves them alone (as before the rule existed).
  describe "approve / decline of a past pending booking" do
    let(:past) { booking_of(user, start_time: "2026-11-30 10:00", end_time: "2026-11-30 11:00") }

    it "staff approve it" do
      log_in!(staff)
      put sub_space_booking_approve_path(sub_space_booking_id: past.id)
      expect(flash[:notice]).to eq("Booking for #{subspace.name} approved successfully.")
      expect(status_name(past)).to eq("Approved")
      expect(past.reload.approved_by_id).to eq(staff.id)
      expect(past.approved_at).to eq(BookingClock::NOW)
    end

    it "staff decline it" do
      log_in!(staff)
      put sub_space_booking_decline_path(sub_space_booking_id: past.id)
      expect(flash[:notice]).to eq("Booking for #{subspace.name} declined successfully.")
      expect(status_name(past)).to eq("Declined")
    end

    it "admins bulk approve and bulk decline it" do
      log_in!(admin)
      put bulk_approve_decline_sub_space_booking_index_path,
          params: { sub_space_booking_ids: [past.id], bulk_status: "approve" }
      expect(flash[:notice]).to eq("Bookings approved successfully.")
      expect(status_name(past)).to eq("Approved")

      put bulk_approve_decline_sub_space_booking_index_path,
          params: { sub_space_booking_ids: [past.id], bulk_status: "decline" }
      expect(flash[:notice]).to eq("Bookings declined successfully.")
      expect(status_name(past)).to eq("Declined")
    end

    it "admins toggle it public" do
      log_in!(admin)
      put sub_space_booking_publish_path(sub_space_booking_id: past.id)
      expect(flash[:notice]).to eq("Booking made public successfully.")
      expect(past.reload.public).to be(true)
    end
  end
end
