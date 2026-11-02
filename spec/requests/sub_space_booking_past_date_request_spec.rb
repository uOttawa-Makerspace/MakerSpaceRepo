# frozen_string_literal: true

require "rails_helper"

# Past-date rule (user decision 2026-10-25): bookings may not be created
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

    # Admin blocks over existing bookings are intended, but
    # "admins included" covers blocks: a past-dated block is refused too.
    it "refuses a past-dated admin block" do
      log_in!(admin)
      create_booking(start_time: "2026-11-30 10:00", end_time: "2026-11-30 11:00",
                     name: "PastBlock", blocking: true)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [past_error])
      expect(SubSpaceBooking.where(name: "PastBlock")).to be_empty
    end

    # A form-encoded body is not param-wrapped, so sub_space_booking is really
    # missing; ApplicationController#parameter_missing answers (it used to 500).
    it "answers a missing sub_space_booking with the ParameterMissing handler (JSON 400, HTML redirect)" do
      log_in!(user)
      post sub_space_booking_index_path, params: { unrelated: "x" },
                                         headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("sub_space_booking")

      post sub_space_booking_index_path, params: { unrelated: "x" }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("sub_space_booking")
      expect(SubSpaceBooking.count).to eq(0)
    end

    it "gives a non-admin past block the forbidden answer, not the past-date error" do
      log_in!(user)
      create_booking(start_time: "2026-11-30 10:00", end_time: "2026-11-30 11:00",
                     name: "PastBlock", blocking: true)
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq("errors" => ["You do not have permission to block a space."])
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
    # 12-15 are not (the series overshoot still applies).
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

    # One clock read per request: the past check of an occurrence and its save
    # cannot disagree. Simulated by moving the clock 61 s on after every past
    # check, so any second clock read lands in a later minute.
    it "judges every occurrence against one clock read, even when the minute turns mid-request" do
      log_in!(user)
      allow(SubSpaceBooking).to receive(:start_in_past?).and_wrap_original do |original, *args|
        original.call(*args).tap { travel(61.seconds) }
      end
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2026-12-01 12:00", # this minute
             end_time: "2026-12-01 13:00", name: "Edge", description: "D",
             recurring: true, recurring_frequency: "weekly", recurring_end: "2026-12-15"
           } }
      expect(response).to have_http_status(:no_content)
      expect(walls_of("Edge")).to eq(["2026-12-01 12:00", "2026-12-08 12:00", "2026-12-15 12:00"])
    end

    # a failed occurrence does not stop the series and the answer is
    # 422. Changed: the mail now goes out for the first occurrence actually
    # booked (before, a failed first attempt meant no mail at all).
    it "mails for the first booked occurrence when an earlier one conflicts" do
      managed = create(:space, :with_space_managers)
      room = create(:sub_space, space: managed, approval_required: true, max_automatic_approval_hour: nil)
      create(:sub_space_booking, sub_space: room, user: admin, name: "Grabber", blocking: true,
                                 start_time: Time.zone.parse("2026-12-08 10:30"),
                                 end_time: Time.zone.parse("2026-12-08 11:30"))
      log_in!(user)
      post_series(start_on: "2026-11-17", end_on: "2026-12-15", name: "Mailed", room: room)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."],
                                         "booked" => 1, "failed" => ["2026-12-08"],
                                         "summary" => "Booked 1 of 2 occurrences. Not booked: 2026-12-08.")
      expect(walls_of("Mailed")).to eq(["2026-12-15 10:00"])
      expect(ActionMailer::Base.deliveries.map(&:subject)).to eq(["Booking needs approval"])
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

    # Coordinator decision: a booking in progress may change
    # its end only, to an end after now.
    describe "a booking in progress (11:00-13:00, now 12:00)" do
      let(:running) { booking_of(user, start_time: "2026-12-01 11:00", end_time: "2026-12-01 13:00") }

      it "may be extended or shortened to an end after now" do
        log_in!(user)
        patch_times(running, "2026-12-01 11:00", "2026-12-01 15:00", name: "Longer")
        expect(response).to have_http_status(:ok)
        expect(running.reload.end_time).to eq(Time.zone.parse("2026-12-01 15:00"))
        patch_times(running, "2026-12-01 11:00", "2026-12-01 12:30", name: "Shorter")
        expect(response).to have_http_status(:ok)
        expect(running.reload.end_time).to eq(Time.zone.parse("2026-12-01 12:30"))
      end

      it "may not end in the past: 422 with the end-time error" do
        log_in!(user)
        patch_times(running, "2026-12-01 11:00", "2026-12-01 11:30", name: "Cut")
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq(
          "errors" => ["End time cannot be in the past for a booking that has already started. " \
                       "Pick an end time after now."]
        )
        expect(running.reload.end_time).to eq(Time.zone.parse("2026-12-01 13:00"))
      end

      it "may not move its start" do
        log_in!(user)
        patch_times(running, "2026-12-01 11:30", "2026-12-01 15:00", name: "Shifted")
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq("errors" => [past_error])
        expect(running.reload.start_time).to eq(Time.zone.parse("2026-12-01 11:00"))
      end
    end

    # a booking that has already ended can't have
    # its times changed.
    it "refuses moving an ended booking, even to the future, or giving it a new end" do
      log_in!(user)
      booking = booking_of(user, start_time: "2026-11-20 10:00", end_time: "2026-11-20 11:00")
      ended_error = "End time cannot be changed: this booking has already ended."

      patch_times(booking, "2026-12-04 10:00", "2026-12-04 11:00", name: "Rescheduled")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [ended_error])

      patch_times(booking, "2026-11-20 10:00", "2026-12-05 11:00", name: "Revived")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [ended_error])

      booking.reload
      expect(booking.name).to eq("Existing")
      expect(booking.end_time).to eq(Time.zone.parse("2026-11-20 11:00"))
    end

    it "has a French message for an ended booking" do
      log_in!(user)
      booking = booking_of(user, start_time: "2026-11-20 10:00", end_time: "2026-11-20 11:00")
      patch sub_space_booking_update_path(sub_space_booking_id: booking.id, locale: "fr"), as: :json, params: {
        sub_space_booking: { start_time: "2026-11-20 10:00", end_time: "2026-12-05 11:00", name: "R", description: "D" }
      }
      expect(response.parsed_body["errors"])
        .to eq(["End time ne peut plus être modifiée : cette réservation est déjà terminée."])
    end

    # The duration/week limits use the model's minute-precision test, so
    # resubmitting a stored 09:00:30 as "09:00" is a rename, not a move.
    it "renames a booking stored with seconds even when its room's limits were lowered since" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 1)
      stored = Time.zone.parse("2026-12-03 09:00:30")
      row = create(:sub_space_booking, sub_space: capped, user: user, name: "Mirror",
                                       start_time: stored, end_time: stored + 3.hours)
      log_in!(user)
      patch sub_space_booking_update_path(sub_space_booking_id: row.id), as: :json, params: {
        sub_space_booking: { start_time: "2026-12-03 09:00", end_time: "2026-12-03 12:00",
                             name: "Renamed", description: "D" }
      }
      expect(response).to have_http_status(:ok)
      expect(row.reload.name).to eq("Renamed")
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

  # Review fixes (c21b18c): DST and zoned series, the cap, the truthful
  # partial answer, the transaction, and HTML failures.
  describe "series and failure handling" do
    def post_json_series(start_time:, end_time:, recurring_end:, name:, frequency: "weekly")
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: start_time, end_time: end_time,
             name: name, description: "D", recurring: true,
             recurring_frequency: frequency, recurring_end: recurring_end
           } }
    end

    def toronto_walls(name)
      SubSpaceBooking.where(name: name).order(:start_time)
                     .map { |b| b.start_time.in_time_zone.strftime("%Y-%m-%d %H:%M") }
    end

    def block!(from, to)
      create(:sub_space_booking, sub_space: subspace, user: admin, name: "Block", blocking: true,
                                 start_time: Time.zone.parse(from), end_time: Time.zone.parse(to))
    end

    # DST: the overlap check uses the zoned instants, so a series that
    # crosses the 2026-11-01 fall-back is checked against blocks at the right
    # hour on both sides of the change.
    it "checks a series across the November DST change against blocks at their real hour" do
      travel_to(Time.zone.local(2026, 10, 20, 12, 0))
      block!("2026-11-04 09:00", "2026-11-04 10:00") # touches 10:00 EST: no conflict
      block!("2026-11-11 10:30", "2026-11-11 11:30") # overlaps 10:00-11:00 EST
      log_in!(user)
      post_json_series(start_time: "2026-10-21 10:00", end_time: "2026-10-21 11:00",
                       recurring_end: "2026-11-11", name: "Fall")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."],
                                         "booked" => 3, "failed" => ["2026-11-11"],
                                         "summary" => "Booked 3 of 4 occurrences. Not booked: 2026-11-11.")
      expect(toronto_walls("Fall")).to eq(["2026-10-21 10:00", "2026-10-28 10:00", "2026-11-04 10:00"])
    end

    # Every occurrence derives from the first one's zoned start, so a start
    # with an explicit offset keeps one Toronto wall clock, across DST too.
    it "keeps the first occurrence's Toronto time for a start given with an offset, across the March DST change" do
      log_in!(user)
      post_json_series(start_time: "2027-03-03T15:00:00Z", end_time: "2027-03-03T16:00:00Z",
                       recurring_end: "2027-03-17", name: "Offset")
      expect(response).to have_http_status(:no_content)
      expect(toronto_walls("Offset")).to eq(["2027-03-03 10:00", "2027-03-10 10:00", "2027-03-17 10:00"])
      expect(SubSpaceBooking.where(name: "Offset").order(:start_time).map { |b| b.end_time - b.start_time })
        .to all(eq(1.hour))
    end

    # Round 3: the occurrence cap is gone (365 days is the only cap), and the
    # series is generated once.
    it "generates the series once, and has no occurrence cap besides the 365 days" do
      expect(SubSpaceBookingController::SERIES_MAX_DAYS).to eq(365)
      expect(SubSpaceBookingController.const_defined?(:SERIES_MAX_OCCURRENCES)).to be(false)
      log_in!(user)
      expect_any_instance_of(SubSpaceBookingController)
        .to receive(:series_occurrences).once.and_call_original
      post_json_series(start_time: "2026-12-02 10:00", end_time: "2026-12-02 11:00",
                       recurring_end: "2026-12-16", name: "Once")
      expect(response).to have_http_status(:no_content)
      expect(SubSpaceBooking.where(name: "Once").count).to eq(3)
    end

    # Round 3: each end is its start plus the first occurrence's duration, so
    # a month-end clamp cannot put an end before its start. The start
    # drift (each start advances the previous one) is kept.
    it "keeps every monthly occurrence's duration around month-end (22:00 Jan 30 to 01:00 Jan 31)" do
      log_in!(user)
      post_json_series(start_time: "2027-01-30 22:00", end_time: "2027-01-31 01:00",
                       recurring_end: "2027-04-30", name: "MonthEnd", frequency: "monthly")
      expect(response).to have_http_status(:no_content)
      rows = SubSpaceBooking.where(name: "MonthEnd").order(:start_time)
      expect(rows.map { |b| b.start_time.in_time_zone.strftime("%Y-%m-%d %H:%M") }).to eq(
        ["2027-01-30 22:00", "2027-02-28 22:00", "2027-03-28 22:00", "2027-04-28 22:00", "2027-05-28 22:00"]
      )
      expect(rows.map { |b| b.end_time - b.start_time }).to all(eq(3.hours))
    end

    it "answers a malformed recurring_end with the invalid-parameters 422" do
      log_in!(user)
      post_json_series(start_time: "2026-12-02 10:00", end_time: "2026-12-02 11:00",
                       recurring_end: "not-a-date", name: "BadEnd")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => "Invalid recurring parameters")
      expect(SubSpaceBooking.where(name: "BadEnd")).to be_empty
    end

    it "redirects a successful HTML create to the room's calendar with the notice" do
      log_in!(user)
      post sub_space_booking_index_path, params: { sub_space_booking: {
        sub_space_id: subspace.id, start_time: "2026-12-02 10:00", end_time: "2026-12-02 11:00",
        name: "HtmlOk", description: "D"
      } }
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: subspace.id)
      )
      expect(flash[:notice]).to eq("Booking for #{subspace.name} created successfully.")
      expect(SubSpaceBooking.where(name: "HtmlOk").count).to eq(1)
    end

    it "answers a partial series truthfully: no success notice, the count and the failed dates" do
      block!("2026-12-09 10:30", "2026-12-09 11:30")
      log_in!(user)
      post_json_series(start_time: "2026-12-02 10:00", end_time: "2026-12-02 11:00",
                       recurring_end: "2026-12-16", name: "Partial")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["booked"]).to eq(2)
      expect(response.parsed_body["failed"]).to eq(["2026-12-09"])
      expect(response.parsed_body["summary"]).to eq("Booked 2 of 3 occurrences. Not booked: 2026-12-09.")
      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to eq("Booked 2 of 3 occurrences. Not booked: 2026-12-09.")
      expect(toronto_walls("Partial")).to eq(["2026-12-02 10:00", "2026-12-16 10:00"])
    end

    it "answers a partial series with an HTML redirect and the summary alert when HTML is asked for" do
      block!("2026-12-09 10:30", "2026-12-09 11:30")
      log_in!(user)
      post sub_space_booking_index_path,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2026-12-02 10:00", end_time: "2026-12-02 11:00",
             name: "PartialHtml", description: "D", recurring: true,
             recurring_frequency: "weekly", recurring_end: "2026-12-16"
           } }.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "text/html" }
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: subspace.id)
      )
      expect(flash[:alert]).to eq("Booked 2 of 3 occurrences. Not booked: 2026-12-09.")
      expect(flash[:notice]).to be_nil
    end

    it "sets the success notice once a whole series is booked" do
      log_in!(user)
      post_json_series(start_time: "2026-12-02 10:00", end_time: "2026-12-02 11:00",
                       recurring_end: "2026-12-16", name: "Whole")
      expect(response).to have_http_status(:no_content)
      expect(flash[:notice]).to eq("Booking for #{subspace.name} created successfully.")
    end

    # The booking, its status and the link are one transaction: a failure in
    # the middle (here the status, whose booking status does not exist, fails
    # to save) rolls the booking back: no booking is left without a status.
    it "leaves no booking behind when its status cannot be saved" do
      stub_const("BookingStatus::APPROVED", BookingStatus.new(id: -1, name: "Ghost"))
      log_in!(user)
      create_booking(start_time: "2026-12-02 10:00", end_time: "2026-12-02 11:00", name: "Orphan")
      expect(response).to have_http_status(:unprocessable_content)
      expect(SubSpaceBooking.where(name: "Orphan")).to be_empty
    end

    it "redirects an HTML create that fails validation or a limit back to the calendar with the alert" do
      log_in!(user)
      post sub_space_booking_index_path, params: { sub_space_booking: {
        sub_space_id: subspace.id, start_time: "2026-12-02 10:00", end_time: "2026-12-02 11:00",
        name: "", description: "D"
      } }
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: subspace.id)
      )
      expect(flash[:alert]).to eq("Name This field is required.")

      capped = create(:sub_space, space: space, maximum_booking_duration: 1)
      post sub_space_booking_index_path, params: { sub_space_booking: {
        sub_space_id: capped.id, start_time: "2026-12-02 10:00", end_time: "2026-12-02 13:00",
        name: "Long", description: "D"
      } }
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: capped.id)
      )
      expect(flash[:alert]).to eq("You cannot book #{capped.name} for more than 1 hours.")
      expect(SubSpaceBooking.where(name: "Long")).to be_empty
    end
  end

  # Round 3 (c21b18d): update's overlap check and blank times.
  describe "PATCH update, round 3" do
    let(:room_a) { create(:sub_space, space: space) }
    let(:room_b) { create(:sub_space, space: space) }

    def owned(room, from = "2026-12-03 10:00", to = "2026-12-03 11:00")
      booking_of(user, start_time: from, end_time: to).tap { |b| b.update_column(:sub_space_id, room.id) }
    end

    def block_in(room, from, to)
      create(:sub_space_booking, sub_space: room, user: admin, name: "Block", blocking: true,
                                 start_time: Time.zone.parse(from), end_time: Time.zone.parse(to))
    end

    def patch_json(booking, **fields)
      patch sub_space_booking_update_path(sub_space_booking_id: booking.id), as: :json,
            params: { sub_space_booking: { name: "Edited", description: "D" }.merge(fields) }
    end

    it "checks the overlap in the room the booking moves to, not the one it leaves" do
      booking = owned(room_a)
      block_in(room_b, "2026-12-03 10:30", "2026-12-03 11:30")
      log_in!(admin)
      patch_json(booking, start_time: "2026-12-03 10:00", end_time: "2026-12-03 11:00", sub_space_id: room_b.id)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."])
      expect(booking.reload.sub_space_id).to eq(room_a.id)
    end

    it "lets a booking leave a room whose block now covers it" do
      booking = owned(room_a)
      block_in(room_a, "2026-12-03 10:30", "2026-12-03 11:30")
      log_in!(admin)
      patch_json(booking, start_time: "2026-12-03 10:00", end_time: "2026-12-03 11:00", sub_space_id: room_b.id)
      expect(response).to have_http_status(:ok)
      expect(booking.reload.sub_space_id).to eq(room_b.id)
    end

    it "lets the owner rename a booking that an admin later blocked over" do
      booking = owned(room_a)
      block_in(room_a, "2026-12-03 10:30", "2026-12-03 11:30")
      log_in!(user)
      patch_json(booking, start_time: "2026-12-03 10:00", end_time: "2026-12-03 11:00", name: "Renamed")
      expect(response).to have_http_status(:ok)
      expect(booking.reload.name).to eq("Renamed")

      patch_json(booking, start_time: "2026-12-03 10:15", end_time: "2026-12-03 11:00") # a move
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."])
    end

    it "keeps the stored times when start_time and end_time are sent blank or null" do
      booking = owned(room_a)
      log_in!(user)
      patch_json(booking, start_time: "", end_time: nil, name: "Blank")
      expect(response).to have_http_status(:ok)
      booking.reload
      expect(booking.name).to eq("Blank")
      expect(booking.start_time).to eq(Time.zone.parse("2026-12-03 10:00"))
      expect(booking.end_time).to eq(Time.zone.parse("2026-12-03 11:00"))
    end

    it "answers an unparseable start_time with the presence error, not a 500" do
      booking = owned(room_a)
      log_in!(user)
      patch_json(booking, start_time: "garbage", end_time: "2026-12-03 11:00")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["Start time This field is required."])
    end
  end
end
