# frozen_string_literal: true

require "rails_helper"

# Chunk 11 gap-closer for SubSpaceBookingController (everything the role
# matrix spec does not cover): create approval branches and mails, recurring
# series edges, update conflicts and mass assignment, access-request branches,
# the admin index and the feed corners.
#
# All mails are asserted by DELIVERED outcome (recipient + subject).

RSpec.describe "Sub space booking gaps", :booking_clock, type: :request do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    ActionMailer::Base.deliveries.clear
  end

  let(:space) { create(:space) }
  let(:subspace) { create(:sub_space, space: space) }
  let(:user) { create(:user, :regular_user, booking_approval: true) }
  let(:admin) { create(:user, :admin, booking_approval: true) }

  def log_in!(account)
    post login_authentication_path,
         params: { username_email: account.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
    follow_redirect!
  end

  def status_name(booking)
    booking.reload.booking_status.name
  end

  def raw_wall(booking, column = "start_time")
    ActiveRecord::Base.connection.select_value(
      "SELECT #{column}::text FROM sub_space_bookings WHERE id = #{booking.id}"
    )
  end

  def create_booking(target = subspace, as: :json, **extra)
    post sub_space_booking_index_path, as: as,
         params: { sub_space_booking: {
           sub_space_id: target.id, start_time: "2027-03-03 10:00",
           end_time: "2027-03-03 11:00", name: "Fresh", description: "Desc"
         }.merge(extra) }
  end

  def pending_booking(owner, **attrs)
    booking = create(:sub_space_booking,
                     { sub_space: subspace, user: owner,
                       start_time: DateTime.parse("2027-04-03 10:00"),
                       end_time: DateTime.parse("2027-04-03 11:00") }.merge(attrs))
    booking.change_status!(@pending_status)
    booking
  end

  # A blocking row at the given Toronto wall times (the overlap check
  # compares zoned instants).
  def blocking_row(target, start_wall, end_wall)
    row = create(:sub_space_booking, sub_space: target, user: user, name: "Block",
                                     start_time: Time.zone.parse(start_wall),
                                     end_time: Time.zone.parse(end_wall), blocking: true)
    row.change_status!(@approved_status)
    row
  end

  # ------------------------------------------------------------ create: approval

  describe "POST create approval branches" do
    let(:managed_space) { create(:space, :with_space_managers) }

    before { log_in!(user) }

    it "auto-approves an approval_required booking whose duration is <= max_automatic_approval_hour" do
      room = create(:sub_space, space: managed_space, approval_required: true,
                                max_automatic_approval_hour: 1)
      create_booking(room) # exactly 1 hour
      expect(response).to have_http_status(:no_content)
      expect(status_name(SubSpaceBooking.find_by!(name: "Fresh"))).to eq("Approved")
    end

    it "leaves an approval_required booking Pending when it is longer than max_automatic_approval_hour" do
      room = create(:sub_space, space: managed_space, approval_required: true,
                                max_automatic_approval_hour: 1)
      create_booking(room, end_time: "2027-03-03 12:00") # 2 hours
      expect(status_name(SubSpaceBooking.find_by!(name: "Fresh"))).to eq("Pending")
    end

    it "copies a default_public sub space into the booking" do
      room = create(:sub_space, space: space, default_public: true)
      create_booking(room)
      expect(SubSpaceBooking.find_by!(name: "Fresh").public).to be(true)
    end

    it "books a regular user who stays inside the weekly quota" do
      capped = create(:sub_space, space: space, maximum_booking_hours_per_week: 2)
      create_booking(capped)
      expect(response).to have_http_status(:no_content)
      expect(SubSpaceBooking.exists?(name: "Fresh")).to be(true)
    end

    # the quota window is the week of the new
    # booking, not the current calendar week.
    it "books next week while this week is full, and still refuses this week" do
      travel_to(Time.zone.local(2027, 4, 7, 8, 0)) do
        log_in!(user)
        capped = create(:sub_space, space: space, maximum_booking_hours_per_week: 4)
        create(:sub_space_booking, sub_space: capped, user: user, name: "Full",
                                   start_time: DateTime.parse("2027-04-07 10:00"),
                                   end_time: DateTime.parse("2027-04-07 13:00"))
        create_booking(capped, name: "ThisWeek", start_time: "2027-04-08 10:00", end_time: "2027-04-08 13:00")
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first).to start_with("DurationWeek")
        create_booking(capped, name: "NextWeek", start_time: "2027-04-14 10:00", end_time: "2027-04-14 13:00")
        expect(response).to have_http_status(:no_content)
        expect(SubSpaceBooking.where(name: %w[ThisWeek NextWeek]).pluck(:name)).to eq(["NextWeek"])

        # next week now holds 3h: a second 3h booking there is over the quota (it used to be
        # judged against the current week only, so a future week had no limit at all)
        create_booking(capped, name: "NextWeek2", start_time: "2027-04-15 10:00", end_time: "2027-04-15 13:00")
        expect(response).to have_http_status(:unprocessable_content)
        expect(SubSpaceBooking.exists?(name: "NextWeek2")).to be(false)
      end
    end

    # Same fixture as the pinned "backwards weekly quota" rejection in
    # sub_space_booking_request_spec.rb, but for an admin: no quota.
    it "lets an admin skip the weekly quota that rejects a regular user" do
      travel_to(Time.zone.local(2027, 3, 10, 12, 0)) do
        log_in!(admin)
        capped = create(:sub_space, space: space, maximum_booking_hours_per_week: 2)
        existing = 4.hours.ago.to_datetime
        create(:sub_space_booking, sub_space: capped, user: admin, name: "Earlier",
                                   start_time: existing, end_time: existing + 4.hours)
        create_booking(capped, name: "AdminHeavy", start_time: "2027-03-10 13:00",
                               end_time: "2027-03-10 14:00")
        expect(response).to have_http_status(:no_content)
        expect(SubSpaceBooking.exists?(name: "AdminHeavy")).to be(true)
      end
    end

    it "creates a plain booking for a non-blocking overlap of two non-blocking bookings (no conflict check)" do
      create_booking(subspace, name: "First")
      create_booking(subspace, name: "Second")
      expect(response).to have_http_status(:no_content)
      expect(SubSpaceBooking.where(name: %w[First Second]).count).to eq(2)
    end

    # Round 3: an HTML create has no template for the implicit render (the
    # coordinator reports a 500 in a browser), so it redirects to the room's calendar with the notice.
    it "redirects an HTML-format create to the room's calendar with the notice" do
      create_booking(subspace, as: :html)
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: subspace.id)
      )
      expect(flash[:notice]).to eq("Booking for #{subspace.name} created successfully.")
      expect(SubSpaceBooking.find_by!(name: "Fresh").user_id).to eq(user.id)
    end

    it "redirects an HTML create that hits a blocking row with the already-booked flash" do
      blocking_row(subspace, "2027-03-03 09:00", "2027-03-03 12:00")
      create_booking(subspace, as: :html)
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: subspace.id)
      )
      expect(flash[:alert]).to eq("This time slot is already booked.")
      expect(SubSpaceBooking.where(name: "Fresh")).to be_empty
    end

    it "stamps approved_at and approved_by on an admin booking" do
      log_in!(admin)
      frozen = Time.zone.now.change(usec: 0)
      travel_to(frozen)
      create_booking(subspace)
      booking = SubSpaceBooking.find_by!(name: "Fresh")
      expect(booking.approved_by_id).to eq(admin.id)
      expect(booking.approved_at).to eq(frozen)
      expect(status_name(booking)).to eq("Approved")
    end
  end

  describe "POST create mails", :perform_jobs do
    it "a pending booking mails the space managers only" do
      managed = create(:space, :with_space_managers)
      room = create(:sub_space, space: managed, approval_required: true,
                                max_automatic_approval_hour: nil)
      log_in!(user)
      create_booking(room)

      expect(ActionMailer::Base.deliveries.size).to eq(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq("Booking needs approval")
      expect(mail.to).to match_array(managed.space_managers.map(&:email))
    end

    # the mail text says "made in <room> by <booking NAME>", not the user
    it "names the booking title (not the user) in the needs-approval mail body" do
      managed = create(:space, :with_space_managers)
      room = create(:sub_space, space: managed, approval_required: true,
                                max_automatic_approval_hour: nil)
      log_in!(user)
      create_booking(room, name: "Robot Club")
      body = ActionMailer::Base.deliveries.last.body.encoded
      expect(body).to include("A booking has been made in #{room.name} by Robot Club for Desc")
      expect(body).not_to include(user.name)
    end

    it "an auto-approved booking by a regular user delivers two mails: managers first, then the booker" do
      managed = create(:space, :with_space_managers)
      room = create(:sub_space, space: managed, approval_required: false)
      log_in!(user)
      create_booking(room)

      mails = ActionMailer::Base.deliveries
      expect(mails.map(&:subject)).to eq(["Booking automatically approved.", "Booking approved"])
      expect(mails.first.to).to match_array(managed.space_managers.map(&:email))
      expect(mails.last.to).to eq([user.email])
    end

    it "an admin booking delivers just the approved mail to the admin" do
      room = create(:sub_space, space: create(:space, :with_space_managers))
      log_in!(admin)
      create_booking(room)

      expect(ActionMailer::Base.deliveries.map(&:subject)).to eq(["Booking approved"])
      expect(ActionMailer::Base.deliveries.last.to).to eq([admin.email])
    end

    # The mails are queued after the booking is saved, so a delivery failure
    # neither fails the request nor undoes the booking.
    it "answers 204 and keeps the booking when mail delivery fails", perform_jobs: false do
      managed = create(:space, :with_space_managers)
      room = create(:sub_space, space: managed, approval_required: true, max_automatic_approval_hour: nil)
      allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_raise(Net::SMTPFatalError, "550 rejected")
      log_in!(user)
      create_booking(room)

      expect(response).to have_http_status(:no_content)
      expect(status_name(SubSpaceBooking.find_by!(name: "Fresh"))).to eq("Pending")
    end

    it "queues the needs-approval mail instead of delivering it in the request", perform_jobs: false do
      managed = create(:space, :with_space_managers)
      room = create(:sub_space, space: managed, approval_required: true, max_automatic_approval_hour: nil)
      log_in!(user)
      expect { create_booking(room) }.to have_enqueued_mail(BookingMailer, :send_booking_needs_approval)
    end

    it "mails the MTC mailbox and reports the missing managers for a pending booking in a space without managers" do
      room = create(:sub_space, space: space, approval_required: true,
                                max_automatic_approval_hour: nil)
      expect(Rails.error).to receive(:report).with(an_instance_of(RuntimeError), hash_including(severity: :warning))
      log_in!(user)
      create_booking(room)

      expect(response).to have_http_status(:no_content)
      expect(status_name(SubSpaceBooking.find_by!(name: "Fresh"))).to eq("Pending")
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq(["mtc@uottawa.ca"])
    end

    it "mails the MTC mailbox, then the booker, for an auto-approved booking in a space without managers" do
      expect(Rails.error).to receive(:report).with(an_instance_of(RuntimeError), hash_including(severity: :warning))
      log_in!(user)
      create_booking(subspace)
      expect(ActionMailer::Base.deliveries.map(&:subject)).to eq(["Booking automatically approved.", "Booking approved"])
      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([["mtc@uottawa.ca"], [user.email]])
    end
  end

  # ------------------------------------------------------------ recurring edges

  describe "POST create recurring edges" do
    before { log_in!(user) }

    def post_series(name:, frequency: "weekly", end_on: "2027-02-17", start_on: "2027-02-03", recurring: true)
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "#{start_on} 10:00",
             end_time: "#{start_on} 11:00", name: name, description: "D",
             recurring: recurring, recurring_frequency: frequency,
             recurring_end: end_on
           } }
    end

    def walls_of(name)
      SubSpaceBooking.where(name: name).order(:start_time).map { |b| raw_wall(b)[0..9] }
    end

    # recurring_end is the last day an occurrence may fall on.
    it "stops at the last occurrence on or before recurring_end when the end falls mid-period" do
      post_series(name: "Over", end_on: "2027-02-16")
      expect(response).to have_http_status(:no_content)
      expect(walls_of("Over")).to eq(%w[2027-02-03 2027-02-10])
    end

    # a series may span at most 365 days (with
    # weekly the densest, at most 54 occurrences).
    # A full year is still allowed (53 weekly occurrences).
    it "allows a series of exactly a year, and refuses one day more with a 422 (en and fr)" do
      post_series(name: "Year", end_on: "2028-02-03")
      expect(response).to have_http_status(:no_content)
      expect(SubSpaceBooking.where(name: "Year").count).to eq(53)

      post_series(name: "TooLong", end_on: "2028-02-04")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq(
        "errors" => ["Recurring A recurring booking can span at most 365 days."]
      )
      expect(SubSpaceBooking.where(name: "TooLong")).to be_empty

      post sub_space_booking_index_path(locale: "fr"), as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-02-03 10:00", end_time: "2027-02-03 11:00",
             name: "TooLong", description: "D", recurring: true, recurring_frequency: "monthly",
             recurring_end: "2030-02-03"
           } }
      expect(response.parsed_body["errors"]).to eq(
        ["Recurring Une réservation récurrente peut couvrir au plus 365 jours."]
      )
      expect(RecurringBooking.count).to eq(1)
    end

    it "treats any frequency other than 'weekly' as monthly" do
      post_series(name: "Daily", frequency: "daily", start_on: "2027-02-03", end_on: "2027-04-03")
      expect(walls_of("Daily")).to eq(%w[2027-02-03 2027-03-03 2027-04-03])
    end

    it "attaches the whole series to ONE RecurringBooking" do
      post_series(name: "Grouped")
      group_ids = SubSpaceBooking.where(name: "Grouped").pluck(:recurring_booking_id)
      expect(group_ids.uniq.size).to eq(1)
      expect(group_ids.first).to be_present
      expect(RecurringBooking.count).to eq(1)
    end

    # The string "true" (what an HTML form submits) fails the `== true` check:
    # the request books a single, non-recurring booking.
    it "books only a single booking when recurring arrives as the string 'true'" do
      post_series(name: "FormString", recurring: "true")
      expect(response).to have_http_status(:no_content)
      expect(walls_of("FormString")).to eq(%w[2027-02-03])
      expect(SubSpaceBooking.find_by!(name: "FormString").recurring_booking_id).to be_nil
    end

    # When the first occurrence cannot be booked the whole series is refused:
    # nothing is saved, no mail is sent, and one 422 says why.
    it "refuses the whole series when the first occurrence conflicts" do
      blocking_row(subspace, "2027-02-03 10:30", "2027-02-03 11:30")
      expect { post_series(name: "NoFirst") }.not_to change(SubSpaceBooking.where(name: "NoFirst"), :count)
      message = "The series was not created because the first occurrence, 2027-02-03, could not be booked. " \
                "This time slot is already booked."
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."],
                                         "summary" => message)
      expect(flash[:alert]).to eq(message)
      expect(flash[:notice]).to be_nil
      expect(RecurringBooking.count).to eq(0)
    end

    it "answers the refused series in French" do
      blocking_row(subspace, "2027-02-03 10:30", "2027-02-03 11:30")
      post sub_space_booking_index_path(locale: "fr"), as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-02-03 10:00", end_time: "2027-02-03 11:00",
             name: "NoFirstFr", description: "D", recurring: true, recurring_frequency: "weekly",
             recurring_end: "2027-02-17"
           } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["summary"]).to start_with("La série n'a pas été créée")
      expect(SubSpaceBooking.where(name: "NoFirstFr")).to be_empty
    end

    it "keeps a partial series when only a later occurrence conflicts" do
      blocking_row(subspace, "2027-02-10 10:30", "2027-02-10 11:30")
      post_series(name: "LaterOnly")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("booked" => 2, "failed" => ["2027-02-10"])
      expect(walls_of("LaterOnly")).to eq(%w[2027-02-03 2027-02-17])
    end

    it "mails only for the first occurrence of a pending series", :perform_jobs do
      managed = create(:space, :with_space_managers)
      room = create(:sub_space, space: managed, approval_required: true,
                                max_automatic_approval_hour: nil)
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: room.id, start_time: "2027-02-03 10:00",
             end_time: "2027-02-03 11:00", name: "Mailed", description: "D",
             recurring: true, recurring_frequency: "weekly", recurring_end: "2027-02-17"
           } }

      expect(SubSpaceBooking.where(name: "Mailed").count).to eq(3)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.subject).to eq("Booking needs approval")
    end

    # The series is built from wall-clock strings that the model parses in the
    # app zone (America/Toronto), so every occurrence keeps its Toronto time and
    # the stored UTC instant moves by one hour across the DST change.
    it "keeps 10:00 Toronto for every occurrence of a weekly series across the March 2027 DST start" do
      post_series(name: "SpringSeries", start_on: "2027-03-10", end_on: "2027-03-24")
      expect(response).to have_http_status(:no_content)
      rows = SubSpaceBooking.where(name: "SpringSeries").order(:start_time)
      expect(rows.map { |b| raw_wall(b) }).to eq(
        ["2027-03-10 15:00:00", "2027-03-17 14:00:00", "2027-03-24 14:00:00"]
      )
      expect(rows.map { |b| raw_wall(b, "end_time") }).to eq(
        ["2027-03-10 16:00:00", "2027-03-17 15:00:00", "2027-03-24 15:00:00"]
      )
      expect(rows.map { |b| b.start_time.in_time_zone("America/Toronto").strftime("%F %H:%M %Z") }).to eq(
        ["2027-03-10 10:00 EST", "2027-03-17 10:00 EDT", "2027-03-24 10:00 EDT"]
      )
    end

    it "keeps 10:00 Toronto for every occurrence of a weekly series across the November 2027 DST end" do
      post_series(name: "FallSeries", start_on: "2027-10-31", end_on: "2027-11-14")
      expect(response).to have_http_status(:no_content)
      rows = SubSpaceBooking.where(name: "FallSeries").order(:start_time)
      expect(rows.map { |b| raw_wall(b) }).to eq(
        ["2027-10-31 14:00:00", "2027-11-07 15:00:00", "2027-11-14 15:00:00"]
      )
      expect(rows.map { |b| b.start_time.in_time_zone("America/Toronto").strftime("%F %H:%M %Z") }).to eq(
        ["2027-10-31 10:00 EDT", "2027-11-07 10:00 EST", "2027-11-14 10:00 EST"]
      )
    end

  end

  # ------------------------------------------------------------ create: limit boundaries

  describe "POST create boundaries (touching intervals, duration cap, weekly quota)" do
    before { log_in!(user) }

    # the overlap is exact on half-open intervals [start, end): back-to-back
    # bookings are fine, any positive overlap (even one minute) is refused.
    it "accepts bookings that touch a blocking booking at either end and rejects a real overlap" do
      blocking_row(subspace, "2027-03-03 09:00", "2027-03-03 12:00")

      create_booking(subspace, name: "After", start_time: "2027-03-03 12:00", end_time: "2027-03-03 13:00")
      expect(response).to have_http_status(:no_content)
      create_booking(subspace, name: "Before", start_time: "2027-03-03 08:00", end_time: "2027-03-03 09:00")
      expect(response).to have_http_status(:no_content)
      expect(SubSpaceBooking.where(name: %w[After Before]).count).to eq(2)

      create_booking(subspace, name: "Overlap", start_time: "2027-03-03 11:59", end_time: "2027-03-03 12:59")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."])
      create_booking(subspace, name: "OverlapEarly", start_time: "2027-03-03 08:01", end_time: "2027-03-03 09:01")
      expect(response).to have_http_status(:unprocessable_content)
      expect(SubSpaceBooking.where(name: %w[Overlap OverlapEarly])).to be_empty
    end

    it "accepts a booking of exactly maximum_booking_duration and rejects one minute more" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 4)

      create_booking(capped, name: "Exact", start_time: "2027-03-03 10:00", end_time: "2027-03-03 14:00")
      expect(response).to have_http_status(:no_content)
      expect(SubSpaceBooking.exists?(name: "Exact")).to be(true)

      create_booking(capped, name: "OneMore", start_time: "2027-03-04 10:00", end_time: "2027-03-04 14:01")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq(
        "errors" => ["DurationHour You cannot book #{capped.name} for more than 4 hours."]
      )
      expect(SubSpaceBooking.exists?(name: "OneMore")).to be(false)
    end

    it "accepts a booking that lands exactly on the weekly quota and rejects one minute over" do
      travel_to(Time.zone.local(2027, 4, 7, 8, 0)) do
        log_in!(user)
        capped = create(:sub_space, space: space, maximum_booking_hours_per_week: 4)
        create(:sub_space_booking, sub_space: capped, user: user, name: "Earlier",
                                   start_time: DateTime.parse("2027-04-07 10:00"),
                                   end_time: DateTime.parse("2027-04-07 12:00"))

        create_booking(capped, name: "OneOver", start_time: "2027-04-08 10:00", end_time: "2027-04-08 12:01")
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq(
          "errors" => ["DurationWeek You cannot book #{capped.name} for more than 4 hours per week."]
        )
        expect(SubSpaceBooking.exists?(name: "OneOver")).to be(false)

        create_booking(capped, name: "Exact", start_time: "2027-04-08 10:00", end_time: "2027-04-08 12:00")
        expect(response).to have_http_status(:no_content)
        expect(SubSpaceBooking.exists?(name: "Exact")).to be(true)
      end
    end

    # 2027-04-11 21:00 Toronto (EDT) is Monday 2027-04-12 01:00 UTC: the Toronto
    # week (Mon 04-05 .. Sun 04-11) holds the Tuesday booking, the UTC week does not.
    it "counts the weekly quota in the Toronto week, not the UTC week (Sunday evening Toronto)" do
      travel_to(Time.zone.local(2027, 4, 7, 8, 0)) do
        log_in!(user)
        capped = create(:sub_space, space: space, maximum_booking_hours_per_week: 2)
        create(:sub_space_booking, sub_space: capped, user: user, name: "Tuesday",
                                   start_time: DateTime.parse("2027-04-06 10:00"),
                                   end_time: DateTime.parse("2027-04-06 12:00"))

        create_booking(capped, name: "SundayEvening", start_time: "2027-04-11 21:00", end_time: "2027-04-11 22:00")
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first).to start_with("DurationWeek")
        expect(SubSpaceBooking.exists?(name: "SundayEvening")).to be(false)
      end
    end
  end

  # ------------------------------------------------------------ update

  describe "PATCH update conflicts and mass assignment" do
    let(:booking) { pending_booking(user) }

    before { log_in!(user) }

    def update_path_for(target)
      sub_space_booking_update_path(sub_space_booking_id: target.id)
    end

    it "answers a JSON conflict with 422 and the TimeSlot error, changing nothing" do
      blocking_row(subspace, "2027-04-03 12:00", "2027-04-03 14:00")
      patch update_path_for(booking), as: :json, params: {
        sub_space_booking: { start_time: "2027-04-03 12:30", end_time: "2027-04-03 13:30",
                             name: "Moved", description: "D" }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."])
      expect(flash[:alert]).to eq("This time slot is already booked.")
      expect(booking.reload.name).not_to eq("Moved")
    end

    it "refuses an update that overlaps a blocking booking by one minute, on either edge, and accepts touching" do
      blocking_row(subspace, "2027-04-03 12:00", "2027-04-03 14:00")
      { ["11:00", "12:01"] => :unprocessable_content, ["13:59", "15:00"] => :unprocessable_content,
        ["11:00", "12:00"] => :ok, ["14:00", "15:00"] => :ok }.each do |(from, to), status|
        patch update_path_for(booking), as: :json, params: {
          sub_space_booking: { start_time: "2027-04-03 #{from}", end_time: "2027-04-03 #{to}",
                               name: "Moved", description: "D" }
        }
        expect(response).to have_http_status(status), "#{from}-#{to} gave #{response.status}"
      end
    end

    it "redirects an HTML conflict back to the edit form" do
      blocking_row(subspace, "2027-04-03 12:00", "2027-04-03 14:00")
      patch update_path_for(booking), params: {
        sub_space_booking: { start_time: "2027-04-03 12:30", end_time: "2027-04-03 13:30",
                             name: "Moved", description: "D" }
      }
      expect(response).to redirect_to(sub_space_booking_edit_path(sub_space_booking_id: booking.id))
      expect(flash[:alert]).to eq("This time slot is already booked.")
      expect(booking.reload.name).not_to eq("Moved")
    end

    # update ignores :blocking and :sub_space_id from non-admins
    # and re-applies the room's maximum booking duration.
    it "ignores blocking and sub_space_id from the owner of a pending booking" do
      other = create(:sub_space, space: space)
      patch update_path_for(booking), params: {
        sub_space_booking: { start_time: "2027-04-03 10:00", end_time: "2027-04-03 11:00",
                             name: "Renamed", description: "D", blocking: true,
                             sub_space_id: other.id }
      }
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: subspace.id)
      )
      booking.reload
      expect(booking.name).to eq("Renamed")
      expect(booking.blocking).to be(false)
      expect(booking.sub_space_id).to eq(subspace.id)
      expect(status_name(booking)).to eq("Pending")
    end

    it "rejects a non-admin stretching a booking past the room's maximum duration (JSON and HTML)" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 1)
      capped_booking = pending_booking(user, sub_space: capped)
      patch update_path_for(capped_booking), as: :json, params: {
        sub_space_booking: { start_time: "2027-04-03 10:00", end_time: "2027-04-04 10:00",
                             name: "Stretched", description: "D" }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].first).to start_with("DurationHour")

      patch update_path_for(capped_booking), params: {
        sub_space_booking: { start_time: "2027-04-03 10:00", end_time: "2027-04-04 10:00",
                             name: "Stretched", description: "D" }
      }
      expect(response).to redirect_to(sub_space_booking_edit_path(sub_space_booking_id: capped_booking.id))
      expect(flash[:alert]).to include("for more than 1 hours")
      expect(capped_booking.reload.name).not_to eq("Stretched")
    end

    # the cap is computed from the values the model
    # stores, so an offset in the param can no longer hide the real duration.
    it "measures the duration cap on the stored times, not on the offset-stripped wall clock" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 1)
      capped_booking = pending_booking(user, sub_space: capped)
      # 10:00 UTC to 10:00 at -12:00 is 12 hours.
      patch update_path_for(capped_booking), as: :json, params: {
        sub_space_booking: { start_time: "2027-04-03T10:00:00+00:00",
                             end_time: "2027-04-03T10:00:00-12:00",
                             name: "Sneaky", description: "D" }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].first).to start_with("DurationHour")
      expect(capped_booking.reload.name).not_to eq("Sneaky")
    end

    # the duration cap, like the weekly quota, only applies when the times move
    it "lets the owner rename a booking longer than a since-lowered duration cap, but not move it" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 1)
      long = pending_booking(user, sub_space: capped,
                                   end_time: DateTime.parse("2027-04-03 13:00")) # 3h, over the 1h cap
      patch update_path_for(long), as: :json, params: {
        sub_space_booking: { start_time: "2027-04-03T10:00:00Z", end_time: "2027-04-03T13:00:00Z",
                             name: "Renamed", description: "D" }
      }
      expect(response).to have_http_status(:ok)
      expect(long.reload.name).to eq("Renamed")

      patch update_path_for(long), as: :json, params: {
        sub_space_booking: { start_time: "2027-04-03T11:00:00Z", end_time: "2027-04-03T14:00:00Z",
                             name: "Moved", description: "D" }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].first).to start_with("DurationHour")
      expect(long.reload.name).to eq("Renamed")
    end

    it "accepts a within-cap update that carries an explicit offset" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 1)
      capped_booking = pending_booking(user, sub_space: capped)
      patch update_path_for(capped_booking), as: :json, params: {
        sub_space_booking: { start_time: "2027-04-03T10:00:00-04:00",
                             end_time: "2027-04-03T11:00:00-04:00",
                             name: "Fine", description: "D" }
      }
      expect(response).to have_http_status(:ok)
      expect(capped_booking.reload.name).to eq("Fine")
    end

    describe "weekly quota" do
      # Wednesday 2027-04-07, 08:00 Toronto (12:00 UTC, the same date): early
      # enough that the 10:00-14:00 moves below do not start in the past.
      let(:wednesday) { Time.zone.local(2027, 4, 7, 8, 0) }
      let(:capped) { create(:sub_space, space: space, maximum_booking_hours_per_week: 3) }

      def week_booking(owner, day, from, to, **attrs)
        create(:sub_space_booking,
               { sub_space: capped, user: owner,
                 start_time: Time.zone.parse("2027-04-#{day} #{from}"),
                 end_time: Time.zone.parse("2027-04-#{day} #{to}") }.merge(attrs))
      end

      def update_times(target, from, to, as: :json, name: "Quota")
        patch update_path_for(target), as: as, params: {
          sub_space_booking: { start_time: "2027-04-07 #{from}", end_time: "2027-04-07 #{to}",
                               name: name, description: "D" }
        }
      end

      it "rejects stretching a pending booking past the room's weekly quota (JSON and HTML)" do
        travel_to(wednesday) do
          log_in!(user)
          week_booking(user, "06", "10:00", "12:00") # 2h already used
          own = week_booking(user, "07", "10:00", "11:00")
          own.change_status!(@pending_status)

          update_times(own, "10:00", "12:00") # 2h + 2h > 3h
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.parsed_body).to eq(
            "errors" =>
              ["DurationWeek You cannot book #{capped.name} for more than 3 hours per week."]
          )

          update_times(own, "10:00", "12:00", as: :html)
          expect(response).to redirect_to(sub_space_booking_edit_path(sub_space_booking_id: own.id))
          expect(flash[:alert]).to include("for more than 3 hours per week")
          expect(own.reload.name).not_to eq("Quota")
          expect(own.end_time - own.start_time).to eq(1.hour)
        end
      end

      it "does not count the booking's own current hours twice" do
        travel_to(wednesday) do
          log_in!(user)
          week_booking(user, "06", "10:00", "12:00")
          own = week_booking(user, "07", "10:00", "11:00")
          own.change_status!(@pending_status)

          update_times(own, "11:00", "12:00") # moved: 2h + 1h = 3h, exactly the quota
          expect(response).to have_http_status(:ok)
          expect(own.reload.name).to eq("Quota")
        end
      end

      # the quota is only re-checked when the times move
      it "lets the owner rename a booking whose week is already over quota, but not move it" do
        travel_to(wednesday) do
          log_in!(user)
          week_booking(user, "06", "10:00", "13:00") # 3h
          own = week_booking(user, "07", "10:00", "13:00") # 3h: 6h in a 3h week
          own.change_status!(@pending_status)

          patch update_path_for(own), as: :json, params: {
            sub_space_booking: { start_time: "2027-04-07 10:00", end_time: "2027-04-07 13:00",
                                 name: "Renamed", description: "D" }
          }
          expect(response).to have_http_status(:ok)
          expect(own.reload.name).to eq("Renamed")

          update_times(own, "11:00", "14:00", name: "Moved")
          expect(response).to have_http_status(:unprocessable_content)
          expect(own.reload.name).to eq("Renamed")
        end
      end

      # the week is the one containing the booking
      it "counts the week of the booking, so moving it to an empty next week is fine" do
        travel_to(wednesday) do
          log_in!(user)
          week_booking(user, "06", "10:00", "12:00") # 2h this week
          own = week_booking(user, "07", "10:00", "11:00")
          own.change_status!(@pending_status)

          patch update_path_for(own), as: :json, params: {
            sub_space_booking: { start_time: "2027-04-14 10:00", end_time: "2027-04-14 13:00",
                                 name: "NextWeek", description: "D" }
          }
          expect(response).to have_http_status(:ok)
          expect(own.reload.name).to eq("NextWeek")
        end
      end

      it "ignores other users' bookings and the quota of an admin" do
        travel_to(wednesday) do
          week_booking(create(:user, :regular_user), "06", "10:00", "16:00")
          log_in!(user)
          own = week_booking(user, "07", "10:00", "11:00")
          own.change_status!(@pending_status)
          update_times(own, "10:00", "12:00")
          expect(response).to have_http_status(:ok)

          log_in!(admin)
          week_booking(admin, "06", "10:00", "16:00")
          update_times(own, "10:00", "14:00", name: "AdminHeavy")
          expect(response).to have_http_status(:ok)
          expect(own.reload.name).to eq("AdminHeavy")
        end
      end
    end

    it "lets an admin set blocking, move rooms and exceed the duration cap" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 1)
      log_in!(admin)
      patch update_path_for(booking), params: {
        sub_space_booking: { start_time: "2027-04-03 10:00", end_time: "2027-04-04 10:00",
                             name: "Admin", description: "D", blocking: true,
                             sub_space_id: capped.id }
      }
      booking.reload
      expect(booking.blocking).to be(true)
      expect(booking.sub_space_id).to eq(capped.id)
      expect(booking.end_time - booking.start_time).to eq(24.hours)
    end

    # The overlap check now uses the booking's own (zoned) times instead of
    # re-parsing the raw params, so an update without start_time or
    # end_time keeps the stored times.
    it "keeps the stored times when start_time and end_time are missing" do
      start_before = booking.start_time
      patch update_path_for(booking), params: { sub_space_booking: { name: "NoTimes" } }
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: subspace.id)
      )
      expect(booking.reload.name).to eq("NoTimes")
      expect(booking.start_time).to eq(start_before)
    end
  end

  # ------------------------------------------------------------ access requests

  describe "request_access routing", :perform_jobs do
    let(:applicant) { create(:user, :regular_user, booking_approval: false) }

    before do
      log_in!(applicant)
      ActionMailer::Base.deliveries.clear
    end

    def request_access(params)
      put request_access_sub_space_booking_index_path, params: { comments: "please" }.merge(params)
    end

    it "sends a GNG request to makerlab@uottawa.ca" do
      request_access(identity: "GNG")
      expect(flash[:notice]).to eq("Access request submitted successfully.")
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(["makerlab@uottawa.ca"])
      expect(mail.subject).to eq("Booking approval request sent")
      expect(mail.body.encoded).to include(applicant.name)
    end

    it "sends an Other request to mtc@uottawa.ca" do
      request_access(identity: "Other")
      expect(ActionMailer::Base.deliveries.last.to).to eq(["mtc@uottawa.ca"])
    end

    it "sends any unrecognised identity to the Other mailbox and the request is rejected by validation" do
      request_access(identity: "Wizard")
      # the UBA identity vocabulary is closed, so nothing is saved and no mail goes out
      expect(flash[:alert]).to eq("Identity Selection is not valid.")
      expect(UserBookingApproval.where(user: applicant)).to be_empty
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "reports a validation alert when no identity is given" do
      request_access({})
      expect(flash[:alert]).to eq("Identity This field is required., Identity Selection is not valid.")
      expect(UserBookingApproval.where(user: applicant)).to be_empty
    end

    it "sends a JMTS request to every manager of the JMTS space" do
      jmts = create(:space, :with_space_managers, name: "JMTS")
      request_access(identity: "JMTS")
      expect(ActionMailer::Base.deliveries.last.to).to match_array(jmts.space_managers.map(&:email))
    end

    it "sends a Staff request to the chosen supervisor" do
      supervisor = create(:user, :staff)
      request_access(identity: "Staff", supervisor: supervisor.id)
      expect(ActionMailer::Base.deliveries.last.to).to eq([supervisor.email])
    end

    # the supervisor must be staff or admin; otherwise nothing is
    # saved or mailed.
    it "rejects a regular user picked as supervisor: no request saved, no mail" do
      random_user = create(:user, :regular_user)
      request_access(identity: "Staff", supervisor: random_user.id)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Please choose a staff member as your supervisor.")
      expect(UserBookingApproval.where(user: applicant)).to be_empty
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "accepts an admin as supervisor" do
      admin_supervisor = create(:user, :admin)
      request_access(identity: "Staff", supervisor: admin_supervisor.id)
      expect(ActionMailer::Base.deliveries.last.to).to eq([admin_supervisor.email])
    end
  end

  describe "approve_access branches" do
    before { log_in!(admin) }

    it "approves an existing request by id" do
      applicant = create(:user, :regular_user, booking_approval: false)
      uba = UserBookingApproval.create!(user: applicant, identity: "GNG", approved: false,
                                        comments: "gng", date: Date.new(2027, 1, 1))
      perform_enqueued_jobs { put approve_access_sub_space_booking_index_path, params: { id: uba.id } }

      expect(response).to redirect_to(sub_space_booking_index_path(anchor: "booking-admin-tab"))
      expect(flash[:notice]).to eq("Access request approved successfully.")
      expect(uba.reload.approved).to be(true)
      expect(uba.staff_id).to eq(admin.id)
      expect(applicant.reload.booking_approval).to be(true)
      expect(ActionMailer::Base.deliveries.last.to).to eq([applicant.email])
    end

    it "tells the admin when the user already has booking access (no change, no mail)" do
      applicant = create(:user, :regular_user, booking_approval: true)
      UserBookingApproval.create!(user: applicant, identity: "Other", approved: true,
                                  comments: "c", date: Date.new(2027, 1, 1))
      perform_enqueued_jobs { put approve_access_sub_space_booking_index_path, params: { user_id: applicant.id } }

      expect(flash[:notice]).to eq("#{applicant.name} already has booking access.")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "answers 404 for an unknown user_id" do
      put approve_access_sub_space_booking_index_path, params: { user_id: 99_999_999 }
      expect(response).to have_http_status(:not_found)
    end

    it "rolls back and flashes the failure when the user record is invalid (RecordInvalid rescue)" do
      applicant = create(:user, :regular_user, booking_approval: false)
      applicant.update_column(:gender, "Unlisted")
      uba = UserBookingApproval.create!(user: applicant, identity: "Other", approved: false,
                                        comments: "c", date: Date.new(2027, 1, 1))
      put approve_access_sub_space_booking_index_path, params: { id: uba.id }

      expect(response).to redirect_to(sub_space_booking_index_path(anchor: "booking-admin-tab"))
      expect(flash[:alert]).to start_with("Failed to approve: ")
      expect(uba.reload.approved).to be(false)
      expect(applicant.reload.booking_approval).to be(false)
    end
  end

  describe "approving access requests that are already approved" do
    let(:admin) { create(:user, :admin, booking_approval: true) }
    let(:applicant) { create(:user, :regular_user, booking_approval: false) }

    before { log_in!(admin) }

    it "approve by id is refused the second time: no mail and the approver is unchanged" do
      uba = UserBookingApproval.create!(user: applicant, identity: "Other", approved: false,
                                        comments: "c", date: Date.new(2027, 1, 1))
      perform_enqueued_jobs { put approve_access_sub_space_booking_index_path, params: { id: uba.id } }
      first_mails = ActionMailer::Base.deliveries.size
      other_admin = create(:user, :admin, booking_approval: true)
      log_in!(other_admin)
      perform_enqueued_jobs { put approve_access_sub_space_booking_index_path, params: { id: uba.id } }

      expect(flash[:notice]).to eq("#{applicant.name} already has booking access.")
      expect(ActionMailer::Base.deliveries.size).to eq(first_mails)
      expect(uba.reload.staff_id).to eq(admin.id)
    end

    it "bulk approve skips requests that are already approved" do
      uba = UserBookingApproval.create!(user: applicant, identity: "Other", approved: true, staff: admin,
                                        comments: "c", date: Date.new(2027, 1, 1))
      applicant.update_column(:booking_approval, true)
      other_admin = create(:user, :admin, booking_approval: true)
      log_in!(other_admin)
      perform_enqueued_jobs do
        put bulk_approve_access_sub_space_booking_index_path, params: { user_booking_approval_ids: [uba.id] }
      end
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(uba.reload.staff_id).to eq(admin.id)
    end
  end

  describe "bulk approve access messages" do
    let(:admin) { create(:user, :admin, booking_approval: true) }

    def request_for(approved:)
      user = create(:user, :regular_user, booking_approval: approved)
      UserBookingApproval.create!(user: user, identity: "Other", approved: approved, staff: (admin if approved),
                                  comments: "c", date: Date.new(2027, 1, 1))
    end

    before { log_in!(admin) }

    it "says all were approved when none were skipped" do
      a = request_for(approved: false)
      put bulk_approve_access_sub_space_booking_index_path, params: { user_booking_approval_ids: [a.id] }
      expect(flash[:notice]).to eq("All selected access requests approved successfully.")
      expect(flash[:alert]).to be_nil
    end

    it "reports the skipped ones when only some were approved" do
      a = request_for(approved: false)
      b = request_for(approved: true)
      put bulk_approve_access_sub_space_booking_index_path, params: { user_booking_approval_ids: [a.id, b.id] }
      expect(flash[:notice]).to eq("Selected access requests approved successfully.")
      expect(flash[:alert]).to eq("1 selected request(s) were already approved and were skipped.")
    end

    it "shows only the alert when everything was skipped" do
      b = request_for(approved: true)
      put bulk_approve_access_sub_space_booking_index_path, params: { user_booking_approval_ids: [b.id] }
      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to eq("1 selected request(s) were already approved and were skipped.")
    end
  end

  describe "bulk approve and decline booking messages" do
    let(:staff) { create(:user, :staff, booking_approval: true) }
    let(:booker) { create(:user, :regular_user, booking_approval: true) }

    before { log_in!(staff) }

    %w[approve decline].each do |action|
      verb = action == "approve" ? "approved" : "declined"

      it "#{action}: no skipped notice when all are pending" do
        b = pending_booking(booker)
        put bulk_approve_decline_sub_space_booking_index_path,
            params: { sub_space_booking_ids: [b.id], bulk_status: action }
        expect(flash[:notice]).to eq("Bookings #{verb} successfully.")
        expect(flash[:alert]).to be_nil
      end

      it "#{action}: notice and alert when only some are pending" do
        b = pending_booking(booker)
        done = pending_booking(booker, start_time: DateTime.parse("2027-04-04 10:00"),
                                       end_time: DateTime.parse("2027-04-04 11:00"))
        done.change_status!(@approved_status)
        put bulk_approve_decline_sub_space_booking_index_path,
            params: { sub_space_booking_ids: [b.id, done.id], bulk_status: action }
        expect(flash[:notice]).to eq("Bookings #{verb} successfully.")
        expect(flash[:alert]).to include("1 selected booking(s)")
      end

      it "#{action}: only the alert when none are pending" do
        done = pending_booking(booker)
        done.change_status!(@approved_status)
        put bulk_approve_decline_sub_space_booking_index_path,
            params: { sub_space_booking_ids: [done.id], bulk_status: action }
        expect(flash[:notice]).to be_nil
        expect(flash[:alert]).to include("1 selected booking(s)")
      end
    end
  end

  describe "deny_access / bulk_approve_access branches" do
    before { log_in!(admin) }

    it "deny_access answers 404 for an unknown request id" do
      put deny_access_sub_space_booking_index_path, params: { id: 99_999_999 }
      expect(response).to have_http_status(:not_found)
    end

    it "bulk_approve_access rewrites an invalid identity to 'Other'" do
      applicant = create(:user, :regular_user, booking_approval: false)
      uba = UserBookingApproval.create!(user: applicant, identity: "Other", approved: false,
                                        comments: "c", date: Date.new(2027, 1, 1))
      uba.update_column(:identity, "Legacy")
      put bulk_approve_access_sub_space_booking_index_path, params: { user_booking_approval_ids: [uba.id] }

      expect(uba.reload.identity).to eq("Other")
      expect(uba.approved).to be(true)
    end

    it "approves nothing and sends no mail when one of the selected requests cannot be approved" do
      good_user = create(:user, :regular_user, booking_approval: false)
      bad_user = create(:user, :regular_user, booking_approval: false)
      bad_user.update_column(:gender, "Unlisted")
      older = UserBookingApproval.create!(user: bad_user, identity: "Other", approved: false,
                                          comments: "c", date: Date.new(2027, 1, 1),
                                          created_at: Time.utc(2027, 1, 1))
      newer = UserBookingApproval.create!(user: good_user, identity: "Other", approved: false,
                                          comments: "c", date: Date.new(2027, 1, 1),
                                          created_at: Time.utc(2027, 2, 1))
      perform_enqueued_jobs do
        put bulk_approve_access_sub_space_booking_index_path,
            params: { user_booking_approval_ids: [older.id, newer.id] }
      end

      expect(flash[:alert]).to start_with("Failed to approve: ")
      expect(newer.reload.approved).to be(false)
      expect(good_user.reload.booking_approval).to be(false)
      expect(older.reload.approved).to be(false)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "deny_access removes the request and clears the user's booking access even when the user record is otherwise invalid" do
      applicant = create(:user, :regular_user, booking_approval: true)
      applicant.update_column(:gender, "Unlisted")
      uba = UserBookingApproval.create!(user: applicant, identity: "Other", approved: true,
                                        comments: "c", date: Date.new(2027, 1, 1))
      put deny_access_sub_space_booking_index_path, params: { id: uba.id }

      expect(flash[:notice]).to eq("Access request declined successfully.")
      expect(UserBookingApproval.exists?(uba.id)).to be(false)
      expect(applicant.reload.booking_approval).to be(false)
    end

    it "deny_access keeps the user's access when removing the request fails" do
      applicant = create(:user, :regular_user, booking_approval: true)
      uba = UserBookingApproval.create!(user: applicant, identity: "Other", approved: true,
                                        comments: "c", date: Date.new(2027, 1, 1))
      allow_any_instance_of(UserBookingApproval).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)
      put deny_access_sub_space_booking_index_path, params: { id: uba.id }

      expect(UserBookingApproval.exists?(uba.id)).to be(true)
      expect(applicant.reload.booking_approval).to be(true)
    end
  end

  # ------------------------------------------------------------ approve emails

  describe "approve / bulk approve mails and state" do
    let(:staff) { create(:user, :staff, booking_approval: true) }
    let(:booker) { create(:user, :regular_user, booking_approval: true) }

    before { log_in!(staff) }

    it "approve delivers the approved mail to the booker" do
      booking = pending_booking(booker)
      perform_enqueued_jobs do
        put sub_space_booking_approve_path(sub_space_booking_id: booking.id)
      end
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([booker.email])
      expect(mail.subject).to eq("Booking approved")
    end

    it "re-approving an approved booking is refused: no mail and the approver is unchanged" do
      booking = pending_booking(booker, approved_by_id: booker.id, approved_at: Time.utc(2027, 1, 1))
      booking.change_status!(@approved_status)
      perform_enqueued_jobs do
        put sub_space_booking_approve_path(sub_space_booking_id: booking.id)
      end
      expect(flash[:alert]).to include("no longer pending")
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(booking.reload.approved_by_id).to eq(booker.id)
      expect(booking.booking_status_id).to eq(@approved_status.id)
    end

    it "declining an approved booking is refused and leaves it approved" do
      booking = pending_booking(booker)
      booking.change_status!(@approved_status)
      put sub_space_booking_decline_path(sub_space_booking_id: booking.id)
      expect(flash[:alert]).to include("no longer pending")
      expect(booking.reload.booking_status_id).to eq(@approved_status.id)
    end

    it "bulk approve skips bookings that are not pending: no mail and the approver is unchanged for them" do
      pending_one = pending_booking(booker)
      done = pending_booking(create(:user, :regular_user, booking_approval: true),
                             start_time: DateTime.parse("2027-04-04 10:00"),
                             end_time: DateTime.parse("2027-04-04 11:00"),
                             approved_by_id: booker.id)
      done.change_status!(@approved_status)
      perform_enqueued_jobs do
        put bulk_approve_decline_sub_space_booking_index_path,
            params: { sub_space_booking_ids: [pending_one.id, done.id], bulk_status: "approve" }
      end
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq([booker.email])
      expect(pending_one.reload.approved_by_id).to eq(staff.id)
      expect(done.reload.approved_by_id).to eq(booker.id)
      expect(flash[:alert]).to include("1 selected booking(s) were no longer pending")
    end

    it "bulk decline leaves an approved booking approved" do
      done = pending_booking(booker)
      done.change_status!(@approved_status)
      put bulk_approve_decline_sub_space_booking_index_path,
          params: { sub_space_booking_ids: [done.id], bulk_status: "decline" }
      expect(done.reload.booking_status_id).to eq(@approved_status.id)
    end

    it "bulk approve delivers one approved mail per booking" do
      b1 = pending_booking(booker)
      b2 = pending_booking(create(:user, :regular_user, booking_approval: true),
                           start_time: DateTime.parse("2027-04-04 10:00"),
                           end_time: DateTime.parse("2027-04-04 11:00"))
      perform_enqueued_jobs do
        put bulk_approve_decline_sub_space_booking_index_path,
            params: { sub_space_booking_ids: [b1.id, b2.id], bulk_status: "approve" }
      end
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to contain_exactly(b1.user.email, b2.user.email)
    end
  end

  # ------------------------------------------------------------ index

  describe "GET index" do
    let(:managed) { create(:space, :with_space_managers) }

    it "builds the room rules sentence from the sub space settings" do
      room = create(:sub_space, space: space, maximum_booking_duration: 4,
                                maximum_booking_hours_per_week: 10, default_public: true,
                                approval_required: true, max_automatic_approval_hour: 2)
      log_in!(user)
      get sub_space_booking_index_path, params: { room: room.id }

      expect(response).to have_http_status(:ok)
      text = Capybara.string(response.body).find("p.alert-info").text.squish
      expect(text).to eq(
        "#{room.name} has a maximum booking duration of 4 hours, has a maximum booking hours per person per week of 10 hours, " \
        "bookings (Name and Description of event) are public by default, and Bookings require manual approval, " \
        "bookings of 2 hours or less will be automatically approved"
      )
    end

    it "says bookings need manual approval when there is no automatic-approval hour" do
      room = create(:sub_space, space: space, approval_required: true, max_automatic_approval_hour: nil)
      log_in!(user)
      get sub_space_booking_index_path, params: { room: room.id }
      text = Capybara.string(response.body).find("p.alert-info").text.squish
      expect(text).to eq("#{room.name} bookings will require manual approval")
    end

    it "404s for an unknown room" do
      log_in!(user)
      get sub_space_booking_index_path, params: { room: 99_999_999 }
      expect(response).to have_http_status(:not_found)
    end

    it "lists the user's own bookings newest first" do
      older = pending_booking(user, name: "OlderMine")
      newer = pending_booking(user, name: "NewerMine", start_time: DateTime.parse("2027-05-03 10:00"),
                                    end_time: DateTime.parse("2027-05-03 11:00"))
      pending_booking(create(:user, :regular_user, booking_approval: true), name: "NotMine")
      log_in!(user)
      get sub_space_booking_index_path

      body = response.body
      expect(body).to include("NewerMine", "OlderMine")
      expect(body).not_to include("NotMine")
      expect(body.index("NewerMine")).to be < body.index("OlderMine")
    end

    # N+1 pinned: @supervisors reads smj.user per join row
    it "offers the supervisor select with every space manager once, sorted by name", skip_bullet: true do
      create(:space, :with_space_managers) # 2 managers
      shared = create(:user, :admin, name: "Zed Manager")
      other_space = create(:space)
      other_space.space_managers << shared
      space.space_managers << shared
      log_in!(create(:user, :regular_user, booking_approval: false))
      get sub_space_booking_index_path # the select lives in the access-request form

      options = Capybara.string(response.body).all("select#supervisor option", visible: :all).map(&:text)
      expect(options).to eq(options.sort_by(&:downcase))
      expect(options.count("Zed Manager")).to eq(1)
      expect(options.size).to eq(SpaceManagerJoin.all.map(&:user_id).uniq.size)
    end

    # Unused eager load pinned
    it "partitions the admin panel into current and past lists by end time", skip_bullet: true do
      travel_to(Time.zone.local(2027, 6, 15, 12, 0)) do
        log_in!(admin)
        pending_booking(user, name: "FuturePending", start_time: DateTime.parse("2027-06-20 10:00"),
                              end_time: DateTime.parse("2027-06-20 11:00"))
        pending_booking(user, name: "PastPending", start_time: DateTime.parse("2027-06-10 10:00"),
                              end_time: DateTime.parse("2027-06-10 11:00"))
        approved = pending_booking(user, name: "FutureApproved", start_time: DateTime.parse("2027-06-21 10:00"),
                                         end_time: DateTime.parse("2027-06-21 11:00"))
        approved.change_status!(@approved_status)
        declined = pending_booking(user, name: "PastDeclined", start_time: DateTime.parse("2027-06-09 10:00"),
                                         end_time: DateTime.parse("2027-06-09 11:00"))
        declined.change_status!(@declined_status)

        get sub_space_booking_index_path
        expect(response).to have_http_status(:ok)
        page = Capybara.string(response.body)
        section = ->(id) { page.find("##{id}", visible: :all).text }

        expect(section.call("pending-accordion")).to include("FuturePending")
        expect(section.call("pending-accordion")).not_to include("PastPending")
        expect(section.call("past-pending-accordion")).to include("PastPending")
        expect(section.call("approved-accordion")).to include("FutureApproved")
        expect(section.call("declined-accordion")).not_to include("PastDeclined")
        expect(section.call("past-declined-accordion")).to include("PastDeclined")
      end
    end
  end

  # ------------------------------------------------------------ feed corners

  describe "GET bookings feed corners" do
    let(:owner) { create(:user, :regular_user, booking_approval: true) }

    def feed_booking(**attrs)
      booking = create(:sub_space_booking,
                       { sub_space: subspace, user: owner,
                         start_time: DateTime.parse("2027-04-03 10:00"),
                         end_time: DateTime.parse("2027-04-03 11:00") }.merge(attrs))
      booking.change_status!(@approved_status)
      booking
    end

    def feed(as_user)
      log_in!(as_user)
      get bookings_sub_space_booking_index_path, params: { room: subspace.id }
      expect(response).to have_http_status(:ok)
      response.parsed_body
    end

    it "shows a public blocking booking with its full title" do
      feed_booking(name: "Open", description: "Day", public: true, blocking: true)
      expect(feed(user).first["title"]).to eq("Open - Day")
    end

    it "shows the owner their own non-public blocking booking as Space Blocked (non-admin)" do
      feed_booking(name: "Mine", description: "D", public: false, blocking: true)
      expect(feed(owner).first["title"]).to eq("Space Blocked")
    end

    it "shows an admin their own booking without the owner-name suffix" do
      feed_booking(name: "AdminOwn", description: "D", user: admin)
      expect(feed(admin).first["title"]).to eq("AdminOwn - D")
    end

    it "lists the other bookings of the room when one booking has no status" do
      fine = feed_booking(name: "Fine", description: "D")
      broken = feed_booking(name: "Broken", description: "D",
                            start_time: DateTime.parse("2027-04-04 10:00"),
                            end_time: DateTime.parse("2027-04-04 11:00"))
      broken.update_column(:booking_status_id, nil)
      log_in!(user)
      get bookings_sub_space_booking_index_path, params: { room: subspace.id }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).map { |event| event["id"] }).to eq(["booking_#{fine.id}_#{subspace.id}"])
    end
  end
end
