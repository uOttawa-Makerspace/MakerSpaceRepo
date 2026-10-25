# frozen_string_literal: true

require "rails_helper"

# Chunk 11 gap-closer for SubSpaceBookingController (everything the role
# matrix spec does not cover): create approval branches and mails, recurring
# series edges, update conflicts and mass assignment, access-request branches,
# the admin index and the feed corners.
#
# All mails are asserted by DELIVERED outcome (recipient + subject).

RSpec.describe "Sub space booking gaps", type: :request do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
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
    booking.reload.sub_space_booking_status.booking_status.name
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
    booking.sub_space_booking_status.update!(booking_status_id: @pending_status.id)
    booking
  end

  def blocking_row(target, start_wall, end_wall)
    row = create(:sub_space_booking, sub_space: target, user: user, name: "Block",
                                     start_time: DateTime.parse(start_wall),
                                     end_time: DateTime.parse(end_wall), blocking: true)
    row.sub_space_booking_status.update!(booking_status_id: @approved_status.id)
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

    # Same fixture as the pinned "backwards weekly quota" rejection in
    # sub_space_booking_request_spec.rb (D-B05), but for an admin: no quota.
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

    it "answers an HTML-format create with an empty 204 as well" do
      create_booking(subspace, as: :html)
      expect(response).to have_http_status(:no_content)
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

  describe "POST create mails" do
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

    # WART(D-B34): the mail text says "made in <room> by <booking NAME>", not the user
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

    # WART(D-B33): with no space managers the needs-approval mail is silently
    # skipped, so a Pending booking waits with nobody notified.
    # WART(D-B35): mails are sent with deliver_now inside the request, so an SMTP
    # failure turns into a 500 AFTER the booking and its status were saved.
    it "answers 500 when delivery fails, but the booking is already saved" do
      managed = create(:space, :with_space_managers)
      room = create(:sub_space, space: managed, approval_required: true, max_automatic_approval_hour: nil)
      allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_raise(Net::SMTPFatalError, "550 rejected")
      log_in!(user)
      create_booking(room)

      expect(response).to have_http_status(:internal_server_error)
      expect(status_name(SubSpaceBooking.find_by!(name: "Fresh"))).to eq("Pending")
    end

    it "sends nothing for a pending booking when the space has no managers" do
      room = create(:sub_space, space: space, approval_required: true,
                                max_automatic_approval_hour: nil)
      log_in!(user)
      create_booking(room)

      expect(response).to have_http_status(:no_content)
      expect(status_name(SubSpaceBooking.find_by!(name: "Fresh"))).to eq("Pending")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "sends only the booker's approved mail for an auto-approved booking in a space without managers" do
      log_in!(user)
      create_booking(subspace)
      expect(ActionMailer::Base.deliveries.map(&:subject)).to eq(["Booking approved"])
      expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
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

    # WART(D-B29): the loop books `start + recurrence` while `start < recurring_end`,
    # so a series ending mid-period overshoots recurring_end by one occurrence.
    it "books one occurrence PAST recurring_end when the end falls mid-period" do
      post_series(name: "Over", end_on: "2027-02-16")
      expect(response).to have_http_status(:no_content)
      expect(walls_of("Over")).to eq(%w[2027-02-03 2027-02-10 2027-02-17])
    end

    # WART(D-B29): there is no cap on the number of occurrences.
    it "has no cap: a one-year weekly series creates every occurrence in one request" do
      post_series(name: "Year", end_on: "2028-02-03")
      expect(response).to have_http_status(:no_content)
      expect(SubSpaceBooking.where(name: "Year").count).to eq(54)
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

    # WART(D-B30): when the FIRST occurrence conflicts the request already
    # rendered 422, yet the loop carries on and books the rest of the series.
    it "still creates the later occurrences when the first one conflicts (422 with a partial series)" do
      blocking_row(subspace, "2027-02-03 10:30", "2027-02-03 11:30")
      post_series(name: "NoFirst")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => ["TimeSlot This time slot is already booked."])
      expect(walls_of("NoFirst")).to eq(%w[2027-02-10 2027-02-17])
    end

    it "mails only for the first occurrence of a pending series" do
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

    # WART(D-B28): update permits :sub_space_id and :blocking and re-runs none
    # of create's rules (duration cap, weekly quota, approval).
    it "lets the owner of a pending booking turn it into a block, move it to another room and stretch it past the room cap" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 1)
      patch update_path_for(booking), params: {
        sub_space_booking: { start_time: "2027-04-03 10:00", end_time: "2027-04-04 10:00",
                             name: "Stretched", description: "D", blocking: true,
                             sub_space_id: capped.id }
      }
      # the redirect uses the NEW sub_space_id (the update already applied)
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: capped.id)
      )
      booking.reload
      expect(booking.blocking).to be(true)
      expect(booking.sub_space_id).to eq(capped.id)
      expect(booking.end_time - booking.start_time).to eq(24.hours)
      expect(status_name(booking)).to eq("Pending")
    end

    it "raises (500) when start_time or end_time is missing" do
      patch update_path_for(booking), params: { sub_space_booking: { name: "NoTimes" } }
      expect(response).to have_http_status(:internal_server_error)
      expect(booking.reload.name).not_to eq("NoTimes")
    end
  end

  # ------------------------------------------------------------ access requests

  describe "request_access routing" do
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

    # WART(D-B51): the supervisor is not checked to be staff/admin
    it "mails any user picked as supervisor, even a regular user" do
      random_user = create(:user, :regular_user)
      request_access(identity: "Staff", supervisor: random_user.id)
      expect(ActionMailer::Base.deliveries.last.to).to eq([random_user.email])
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

    # WART(D-B37): no surrounding transaction. The default scope orders newest
    # first, so the newer request is approved (and committed) before the older
    # one's invalid user aborts the loop.
    it "keeps the earlier approvals when a later one raises RecordInvalid (partial commit)" do
      good_user = create(:user, :regular_user, booking_approval: false)
      bad_user = create(:user, :regular_user, booking_approval: false)
      bad_user.update_column(:gender, "Unlisted")
      older = UserBookingApproval.create!(user: bad_user, identity: "Other", approved: false,
                                          comments: "c", date: Date.new(2027, 1, 1),
                                          created_at: Time.utc(2027, 1, 1))
      newer = UserBookingApproval.create!(user: good_user, identity: "Other", approved: false,
                                          comments: "c", date: Date.new(2027, 1, 1),
                                          created_at: Time.utc(2027, 2, 1))
      put bulk_approve_access_sub_space_booking_index_path,
          params: { user_booking_approval_ids: [older.id, newer.id] }

      expect(flash[:alert]).to start_with("Failed to approve: ")
      expect(newer.reload.approved).to be(true)
      expect(good_user.reload.booking_approval).to be(true)
      expect(older.reload.approved).to be(false)
    end

    # WART(D-B38): the request is destroyed BEFORE user.save!; a failing save
    # leaves the request deleted behind an unhandled RecordInvalid (422).
    it "deny_access deletes the request even when saving the user then raises RecordInvalid" do
      applicant = create(:user, :regular_user, booking_approval: true)
      applicant.update_column(:gender, "Unlisted")
      uba = UserBookingApproval.create!(user: applicant, identity: "Other", approved: true,
                                        comments: "c", date: Date.new(2027, 1, 1))
      put deny_access_sub_space_booking_index_path, params: { id: uba.id }

      expect(response).to have_http_status(:unprocessable_content)
      expect(UserBookingApproval.exists?(uba.id)).to be(false)
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

    # WART(D-B31): no state guard: re-approving re-sends the mail and moves approved_by
    it "re-approving an approved booking sends the mail again and overwrites approved_by" do
      booking = pending_booking(booker, approved_by_id: booker.id, approved_at: Time.utc(2027, 1, 1))
      booking.sub_space_booking_status.update!(booking_status_id: @approved_status.id)
      perform_enqueued_jobs do
        put sub_space_booking_approve_path(sub_space_booking_id: booking.id)
      end
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(booking.reload.approved_by_id).to eq(staff.id)
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
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq([b1.user.email, b2.user.email])
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

    # N+1 pinned: @supervisors reads smj.user per join row (see defects.md D-PERF15)
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

    # Unused eager load pinned: see defects.md D-PERF16
    it "partitions the admin panel into current and past lists by end time", skip_bullet: true do
      travel_to(Time.zone.local(2027, 6, 15, 12, 0)) do
        log_in!(admin)
        pending_booking(user, name: "FuturePending", start_time: DateTime.parse("2027-06-20 10:00"),
                              end_time: DateTime.parse("2027-06-20 11:00"))
        pending_booking(user, name: "PastPending", start_time: DateTime.parse("2027-06-10 10:00"),
                              end_time: DateTime.parse("2027-06-10 11:00"))
        approved = pending_booking(user, name: "FutureApproved", start_time: DateTime.parse("2027-06-21 10:00"),
                                         end_time: DateTime.parse("2027-06-21 11:00"))
        approved.sub_space_booking_status.update!(booking_status_id: @approved_status.id)
        declined = pending_booking(user, name: "PastDeclined", start_time: DateTime.parse("2027-06-09 10:00"),
                                         end_time: DateTime.parse("2027-06-09 11:00"))
        declined.sub_space_booking_status.update!(booking_status_id: @declined_status.id)

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
      booking.sub_space_booking_status.update!(booking_status_id: @approved_status.id)
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

    # WART(D-B36): SubSpaceBookingStatus.find(nil) raises RecordNotFound (404)
    # and takes the whole room feed down
    it "answers 404 for the whole room when one booking has no status id" do
      feed_booking(name: "Fine", description: "D")
      broken = feed_booking(name: "Broken", description: "D",
                            start_time: DateTime.parse("2027-04-04 10:00"),
                            end_time: DateTime.parse("2027-04-04 11:00"))
      broken.update_column(:sub_space_booking_status_id, nil)
      log_in!(user)
      get bookings_sub_space_booking_index_path, params: { room: subspace.id }
      expect(response).to have_http_status(:not_found)
    end
  end
end
