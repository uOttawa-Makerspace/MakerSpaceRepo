# frozen_string_literal: true

require "rails_helper"

# Chunk 11 gap-closer for SubSpaceBookingController: the guest / regular /
# staff / admin role matrix for every action the first characterization pass
# left unpinned, the severity-1 security pins (D-B01, D-B02, D-B26) and the
# CSRF probe.
#
# The controller's gates (sub_space_booking_controller.rb:3-17):
#   user_signed_in        index, request_access, bookings
#   user_admin_or_staff   approve, decline, approve_access, bulk_approve_access,
#                         deny_access, users, get_sub_space_booking
#   user_admin            publish
#   user_booking_belongs  delete, edit, update   (owner OR admin; staff is NOT enough)
#   inline owner/admin    delete_remaining_recurring
#   NO gate at all        bulk_approve_decline
# `current_user` never returns nil (it falls back to User.new), so a guest
# always reaches the role gates, never `user_account`.

RSpec.describe "Sub space booking role matrix", type: :request do
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
  let(:owner) { create(:user, :regular_user, booking_approval: true) }

  def log_in!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
    follow_redirect!
  end

  # Signs in a user of the given role (or nobody for :guest) and returns it.
  def sign_in_as(role)
    return nil if role == :guest

    trait = { regular: :regular_user, staff: :staff, admin: :admin }.fetch(role)
    user = create(:user, trait, booking_approval: true)
    log_in!(user)
    user
  end

  def status_name(booking)
    booking.reload.sub_space_booking_status.booking_status.name
  end

  def pending_booking(user = owner, **attrs)
    booking = create(:sub_space_booking,
                     { sub_space: subspace, user: user,
                       start_time: DateTime.parse("2027-04-03 10:00"),
                       end_time: DateTime.parse("2027-04-03 11:00") }.merge(attrs))
    booking.sub_space_booking_status.update!(booking_status_id: @pending_status.id)
    booking
  end

  def uba_for(user, approved: false, identity: "Other")
    UserBookingApproval.create!(user: user, identity: identity, approved: approved,
                                comments: "please", date: Date.new(2027, 1, 1))
  end

  let(:staff_only_alert) { "You must be an admin or staff to view this page." }
  let(:owner_alert) { "You must be the owner of this booking or an admin to delete it." }

  def expect_bounced_to_root(alert)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(alert)
  end

  # ---------------------------------------------------------------- staff gate

  describe "actions behind user_admin_or_staff" do
    %i[guest regular].each do |role|
      context "as a #{role}" do
        it "approve is bounced and the booking stays Pending" do
          booking = pending_booking
          sign_in_as(role)
          put sub_space_booking_approve_path(sub_space_booking_id: booking.id)
          expect_bounced_to_root(staff_only_alert)
          expect(status_name(booking)).to eq("Pending")
          expect(booking.approved_at).to be_nil
        end

        it "decline is bounced and the booking stays Pending" do
          booking = pending_booking
          sign_in_as(role)
          put sub_space_booking_decline_path(sub_space_booking_id: booking.id)
          expect_bounced_to_root(staff_only_alert)
          expect(status_name(booking)).to eq("Pending")
        end

        it "approve_access is bounced and grants nothing" do
          applicant = create(:user, :regular_user, booking_approval: false)
          sign_in_as(role)
          put approve_access_sub_space_booking_index_path, params: { user_id: applicant.id }
          expect_bounced_to_root(staff_only_alert)
          expect(applicant.reload.booking_approval).to be(false)
          expect(UserBookingApproval.where(user: applicant)).to be_empty
        end

        it "deny_access is bounced and keeps the request" do
          applicant = create(:user, :regular_user, booking_approval: true)
          uba = uba_for(applicant, approved: true)
          sign_in_as(role)
          put deny_access_sub_space_booking_index_path, params: { id: uba.id }
          expect_bounced_to_root(staff_only_alert)
          expect(UserBookingApproval.exists?(uba.id)).to be(true)
          expect(applicant.reload.booking_approval).to be(true)
        end

        it "bulk_approve_access is bounced and approves nothing" do
          applicant = create(:user, :regular_user, booking_approval: false)
          uba = uba_for(applicant)
          sign_in_as(role)
          put bulk_approve_access_sub_space_booking_index_path,
              params: { user_booking_approval_ids: [uba.id] }
          expect_bounced_to_root(staff_only_alert)
          expect(uba.reload.approved).to be(false)
          expect(applicant.reload.booking_approval).to be(false)
        end

        it "get_sub_space_booking is bounced" do
          booking = pending_booking
          sign_in_as(role)
          get get_sub_space_booking_sub_space_booking_index_path, params: { id: booking.id }
          expect_bounced_to_root(staff_only_alert)
        end

        it "users is bounced" do
          sign_in_as(role)
          get users_sub_space_booking_index_path
          expect_bounced_to_root(staff_only_alert)
        end
      end
    end

    %i[staff admin].each do |role|
      context "as #{role}" do
        it "approve flips the booking to Approved, stamps the approver and answers with the admin-tab redirect" do
          booking = pending_booking
          user = sign_in_as(role)
          put sub_space_booking_approve_path(sub_space_booking_id: booking.id)
          expect(response).to redirect_to(sub_space_booking_index_path(anchor: "booking-admin-tab"))
          expect(status_name(booking)).to eq("Approved")
          expect(booking.approved_by_id).to eq(user.id)
        end

        it "decline flips the booking to Declined and leaves approved_at / approved_by untouched" do
          # WART(D-B32): decline neither clears an earlier approval nor mails the booker
          booking = pending_booking(approved_at: Time.utc(2027, 1, 1, 9), approved_by_id: owner.id)
          sign_in_as(role)
          perform_enqueued_jobs do
            put sub_space_booking_decline_path(sub_space_booking_id: booking.id)
          end
          expect(response).to redirect_to(sub_space_booking_index_path(anchor: "booking-admin-tab"))
          expect(status_name(booking)).to eq("Declined")
          expect(booking.approved_at).to eq(Time.utc(2027, 1, 1, 9))
          expect(booking.approved_by_id).to eq(owner.id)
          expect(ActionMailer::Base.deliveries).to be_empty
        end

        it "approve_access with an unknown request id is a 404" do
          sign_in_as(role)
          put approve_access_sub_space_booking_index_path, params: { id: 99_999_999 }
          expect(response).to have_http_status(:not_found)
        end

        it "approve_access by user_id grants access and delivers the accepted mail" do
          applicant = create(:user, :regular_user, booking_approval: false)
          user = sign_in_as(role)
          perform_enqueued_jobs do
            put approve_access_sub_space_booking_index_path, params: { user_id: applicant.id }
          end
          expect(flash[:notice]).to eq("Access granted successfully.")
          expect(applicant.reload.booking_approval).to be(true)
          expect(UserBookingApproval.find_by!(user: applicant).staff_id).to eq(user.id)
          mail = ActionMailer::Base.deliveries.last
          expect(mail.to).to eq([applicant.email])
          expect(mail.subject).to eq("Booking approval request accepted")
        end

        it "deny_access removes the request and revokes access" do
          applicant = create(:user, :regular_user, booking_approval: true)
          uba = uba_for(applicant, approved: true)
          sign_in_as(role)
          put deny_access_sub_space_booking_index_path, params: { id: uba.id }
          expect(flash[:notice]).to eq("Access request declined successfully.")
          expect(UserBookingApproval.exists?(uba.id)).to be(false)
          expect(applicant.reload.booking_approval).to be(false)
        end

        it "bulk_approve_access approves the selected requests and delivers one mail each" do
          applicants = 2.times.map { create(:user, :regular_user, booking_approval: false) }
          ubas = applicants.map { |u| uba_for(u) }
          sign_in_as(role)
          perform_enqueued_jobs do
            put bulk_approve_access_sub_space_booking_index_path,
                params: { user_booking_approval_ids: ubas.map(&:id) }
          end
          expect(flash[:notice]).to eq("All selected access requests approved successfully.")
          expect(ubas.map { |u| u.reload.approved }).to all(be(true))
          expect(ActionMailer::Base.deliveries.flat_map(&:to)).to match_array(applicants.map(&:email))
          expect(ActionMailer::Base.deliveries.map(&:subject).uniq)
            .to eq(["Booking approval request accepted"])
        end

        it "get_sub_space_booking returns the full booking JSON" do
          booking = pending_booking
          sign_in_as(role)
          get get_sub_space_booking_sub_space_booking_index_path, params: { id: booking.id }
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body.keys).to match_array(SubSpaceBooking.column_names)
        end

        it "users returns the JSON user list" do
          sign_in_as(role)
          get users_sub_space_booking_index_path
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body).to be_an(Array)
        end
      end
    end

    it "publish is bounced for staff (admin-only gate)" do
      booking = pending_booking
      sign_in_as(:staff)
      put sub_space_booking_publish_path(sub_space_booking_id: booking.id)
      expect_bounced_to_root("You must be an admin to view this page.")
      expect(booking.reload.public).to be(false)
    end
  end

  describe "publish" do
    it "bounces guests (admin gate) and leaves the booking private" do
      booking = pending_booking(public: false)
      put sub_space_booking_publish_path(sub_space_booking_id: booking.id)
      expect_bounced_to_root("You must be an admin to view this page.")
      expect(booking.reload.public).to be(false)
    end

    it "answers 404 for an unknown booking when an admin publishes" do
      sign_in_as(:admin)
      put sub_space_booking_publish_path(sub_space_booking_id: 99_999_999)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "request_access (user_signed_in gate)" do
    it "redirects guests to the login page with the sign-in alert and records nothing" do
      put request_access_sub_space_booking_index_path, params: { comments: "x", identity: "Other" }
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq("You must be logged in to view this page.")
      expect(UserBookingApproval.count).to eq(0)
    end
  end

  # ------------------------------------------------- owner-or-admin (belongs)

  describe "edit / update / delete (user_booking_belongs: owner or admin only)" do
    let(:booking) { pending_booking }
    let(:patch_params) do
      { sub_space_booking: { start_time: "2027-04-03 12:00", end_time: "2027-04-03 13:00",
                             name: "Changed", description: "D" } }
    end

    %i[guest staff].each do |role|
      context "as a #{role} who is not the owner" do
        it "edit is bounced with the owner-or-admin alert" do
          sign_in_as(role)
          get sub_space_booking_edit_path(sub_space_booking_id: booking.id)
          expect_bounced_to_root(owner_alert)
        end

        it "update is bounced and changes nothing" do
          sign_in_as(role)
          patch sub_space_booking_update_path(sub_space_booking_id: booking.id), params: patch_params
          expect_bounced_to_root(owner_alert)
          expect(booking.reload.name).not_to eq("Changed")
        end

        it "delete is bounced and the booking survives" do
          sign_in_as(role)
          delete sub_space_booking_delete_path(booking.id)
          expect_bounced_to_root(owner_alert)
          expect(SubSpaceBooking.exists?(booking.id)).to be(true)
        end
      end
    end

    it "lets an admin update a PENDING booking of another user" do
      sign_in_as(:admin)
      patch sub_space_booking_update_path(sub_space_booking_id: booking.id), params: patch_params
      expect(flash[:notice]).to eq("Successfully updated booking")
      expect(booking.reload.name).to eq("Changed")
    end

    it "lets an admin edit and update an APPROVED booking (owners cannot, see D-B11)" do
      approved = pending_booking
      approved.sub_space_booking_status.update!(booking_status_id: @approved_status.id)
      sign_in_as(:admin)
      get sub_space_booking_edit_path(sub_space_booking_id: approved.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Booking")
      patch sub_space_booking_update_path(sub_space_booking_id: approved.id), params: patch_params
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: subspace.id)
      )
      expect(approved.reload.name).to eq("Changed")
      expect(status_name(approved)).to eq("Approved")
    end

    it "lets the owner edit a DECLINED booking (only PENDING-by-others and APPROVED are blocked)" do
      declined = pending_booking
      declined.sub_space_booking_status.update!(booking_status_id: @declined_status.id)
      log_in!(owner)
      get sub_space_booking_edit_path(sub_space_booking_id: declined.id)
      expect(response).to have_http_status(:ok)
      patch sub_space_booking_update_path(sub_space_booking_id: declined.id), params: patch_params
      expect(declined.reload.name).to eq("Changed")
      expect(status_name(declined)).to eq("Declined")
    end

    it "lets an admin delete another user's booking and removes both rows" do
      status_id = booking.sub_space_booking_status_id
      sign_in_as(:admin)
      delete sub_space_booking_delete_path(booking.id)
      expect(response).to redirect_to(sub_space_booking_index_path(anchor: "booking-tab"))
      expect(SubSpaceBooking.exists?(booking.id)).to be(false)
      expect(SubSpaceBookingStatus.exists?(status_id)).to be(false)
    end
  end

  describe "bookings without an owner" do
    # WART(D-B52): `booking.user_id == current_user.id` is nil == nil for a guest
    # and a booking with a NULL user_id, so the owner gate passes for guests.
    it "lets a guest update and delete a booking whose user_id is NULL (edit then stops at its own status check)" do
      orphan = pending_booking
      orphan.update_column(:user_id, nil)

      # the owner gate passes (no root redirect); the edit action's own pending/owner check redirects
      get sub_space_booking_edit_path(sub_space_booking_id: orphan.id)
      expect(response).to redirect_to(sub_space_booking_index_path)
      expect(flash[:alert]).to eq("You can't access this subspace booking.")

      patch sub_space_booking_update_path(sub_space_booking_id: orphan.id),
            params: { sub_space_booking: { start_time: "2027-04-03 12:00", end_time: "2027-04-03 13:00",
                                           name: "GuestEdit", description: "D" } }
      expect(orphan.reload.name).to eq("GuestEdit")

      delete sub_space_booking_delete_path(orphan.id)
      expect(SubSpaceBooking.exists?(orphan.id)).to be(false)
    end
  end

  describe "delete_remaining_recurring (inline owner/admin check)" do
    let(:recurring) { RecurringBooking.create! }
    let!(:first_booking) { pending_booking(recurring_booking: recurring) }
    let!(:second_booking) do
      pending_booking(recurring_booking: recurring,
                      start_time: DateTime.parse("2027-04-10 10:00"),
                      end_time: DateTime.parse("2027-04-10 11:00"))
    end

    %i[guest regular staff].each do |role|
      it "bounces a #{role} who is not the owner and deletes nothing" do
        sign_in_as(role)
        delete delete_remaining_recurring_sub_space_booking_path(first_booking.id)
        expect_bounced_to_root("You are not authorized to view this page.")
        expect(SubSpaceBooking.where(id: [first_booking.id, second_booking.id]).count).to eq(2)
      end
    end

    it "lets an admin clear the series" do
      sign_in_as(:admin)
      delete delete_remaining_recurring_sub_space_booking_path(first_booking.id)
      expect(flash[:notice])
        .to eq("Remaining bookings for #{subspace.name} deleted successfully.")
      expect(SubSpaceBooking.where(id: [first_booking.id, second_booking.id])).to be_empty
    end

    it "keeps EARLIER occurrences when deleting from a later booking, and leaves the RecurringBooking row behind" do
      log_in!(owner)
      delete delete_remaining_recurring_sub_space_booking_path(second_booking.id)
      expect(SubSpaceBooking.exists?(first_booking.id)).to be(true)
      expect(SubSpaceBooking.exists?(second_booking.id)).to be(false)
      expect(RecurringBooking.exists?(recurring.id)).to be(true)
    end

    it "answers 404 for an unknown id" do
      sign_in_as(:admin)
      delete delete_remaining_recurring_sub_space_booking_path(99_999_999)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------- severity-1 security pins

  describe "bulk_approve_decline without any gate" do
    # WART(D-B01): bulk_approve_decline has no before_action gate at all (not in
    # user_signed_in, user_admin_or_staff or user_admin) and the dead
    # user_account check never fires, so a GUEST can approve or decline anyone's
    # bookings. An approval is stamped with approved_by_id NULL.
    it "lets a guest bulk-approve other users' bookings (approved_by is NULL, one mail per booking)" do
      b1 = pending_booking
      b2 = pending_booking(start_time: DateTime.parse("2027-04-04 10:00"),
                           end_time: DateTime.parse("2027-04-04 11:00"))

      perform_enqueued_jobs do
        put bulk_approve_decline_sub_space_booking_index_path,
            params: { sub_space_booking_ids: [b1.id, b2.id], bulk_status: "approve" }
      end

      expect(response).to redirect_to(sub_space_booking_index_path(anchor: "booking-admin-tab"))
      expect(flash[:notice]).to eq("Bookings approved successfully.")
      expect([b1, b2].map { |b| status_name(b) }).to eq(%w[Approved Approved])
      expect(b1.approved_by_id).to be_nil
      expect(b1.approved_at).to be_present
      expect(ActionMailer::Base.deliveries.map(&:subject).uniq).to eq(["Booking approved"])
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq([b1.user.email, b2.user.email])
    end

    # WART(D-B01): the guest can also decline (silently, no mail) and re-approve
    # an already declined booking (D-B31: no state guard).
    it "lets a guest decline silently and then re-approve the declined booking" do
      booking = pending_booking

      perform_enqueued_jobs do
        put bulk_approve_decline_sub_space_booking_index_path,
            params: { sub_space_booking_ids: [booking.id], bulk_status: "decline" }
      end
      expect(flash[:notice]).to eq("Bookings declined successfully.")
      expect(status_name(booking)).to eq("Declined")
      expect(ActionMailer::Base.deliveries).to be_empty

      perform_enqueued_jobs do
        put bulk_approve_decline_sub_space_booking_index_path,
            params: { sub_space_booking_ids: [booking.id], bulk_status: "approve" }
      end
      expect(status_name(booking)).to eq("Approved")
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "silently ignores ids that do not exist" do
      put bulk_approve_decline_sub_space_booking_index_path,
          params: { sub_space_booking_ids: [99_999_999], bulk_status: "approve" }
      expect(flash[:notice]).to eq("Bookings approved successfully.")
    end

    it "stamps the signed-in approver on a bulk approval" do
      booking = pending_booking
      staff = sign_in_as(:staff)
      put bulk_approve_decline_sub_space_booking_index_path,
          params: { sub_space_booking_ids: [booking.id], bulk_status: "approve" }
      expect(booking.reload.approved_by_id).to eq(staff.id)
      expect(booking.approved_at).to be_present
    end
  end

  describe "users JSON" do
    # WART(D-B02): `render json: User.all` serializes EVERY column to any staff
    # or admin user: the stored bcrypt `password` and the GitHub `access_token`
    # included.
    it "exposes every user column, password hash and access_token included, to staff" do
      subject_user = create(:user, :regular_user, access_token: "ghp_secret_token_value")
      sign_in_as(:staff)

      get users_sub_space_booking_index_path
      expect(response).to have_http_status(:ok)

      entry = response.parsed_body.find { |u| u["id"] == subject_user.id }
      expect(entry.keys).to match_array(User.column_names)
      expect(entry).to have_key("password")
      expect(entry["password"]).to eq(subject_user.password)
      expect(entry["password"]).to start_with("$2a$")
      expect(entry).to have_key("access_token")
      expect(entry["access_token"]).to eq("ghp_secret_token_value")
      expect(entry["email"]).to eq(subject_user.email)
    end

    it "ignores the query parameter and lists every user" do
      create(:user, :regular_user, name: "Needle Person")
      create(:user, :regular_user, name: "Other Person")
      sign_in_as(:admin)
      get users_sub_space_booking_index_path, params: { query: "Needle" }
      names = response.parsed_body.map { |u| u["name"] }
      expect(names).to include("Needle Person", "Other Person")
      expect(response.parsed_body.size).to eq(User.count)
    end
  end

  describe "CSRF" do
    around do |example|
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    # WART(D-B26/D-J27): application_controller.rb:7-8 declares
    # `protect_from_forgery with: :null_session, only: proc { ... }`. ActionFilter
    # stringifies `only:` (`Array(proc).map(&:to_s)`), so the proc becomes a
    # string that never equals an action name and the verification callback
    # never runs for ANY action of ANY controller (and the declaration replaces
    # the default exception-raising one). The test env disables forgery
    # protection, so this example switches it on for the framework and shows a
    # cross-site-style POST (foreign Origin/Referer, no authenticity token) is
    # still accepted on an ordinary HTML form action. The login POST itself is
    # token-less too.
    it "accepts a token-less cross-site POST on an HTML form action (app-wide)" do
      expect(ActionController::Base.allow_forgery_protection).to be(true)
      user = create(:user, :regular_user, booking_approval: true)
      log_in!(user) # token-less login POST is accepted as well

      expect do
        post sub_space_booking_index_path,
             params: { sub_space_booking: { sub_space_id: subspace.id,
                                            start_time: "2027-03-03 10:00",
                                            end_time: "2027-03-03 11:00",
                                            name: "ForgedByAttacker",
                                            description: "no csrf token sent" } },
             headers: { "Origin" => "https://evil.example",
                        "Referer" => "https://evil.example/forged-form.html" }
      end.to change { SubSpaceBooking.where(name: "ForgedByAttacker").count }.by(1)

      expect(response).to have_http_status(:no_content)
      expect(SubSpaceBooking.find_by!(name: "ForgedByAttacker").user_id).to eq(user.id)
    end
  end
end
