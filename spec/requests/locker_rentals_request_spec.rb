# frozen_string_literal: true

require "rails_helper"

# Characterization spec for LockerRentalsController (chunk 7 "Lockers" —
# doc/architecture.md §5.1 pilot).
#
# Pins the CURRENT observable behavior of the request contract so a later
# refactor (LockerRentals::Request / Approve / Renew / Cancel / Expire use
# cases) can prove no change. Everything below reflects the app as it runs
# today (Rails 8.1, devcontainer); warts are PINNED, not fixed.
#
# Environment notes:
# * Authentication is the custom session, driven with a real login POST
#   (spec/requests/job_orders_request_spec.rb precedent).
# * `LockerOption` is a persisted name/value config table shared across
#   requests; each example resets the two locker keys so behavior starts from
#   the "fresh install" default (lockers_enabled => false).
# * SHOPIFY IS NETWORK-REACHABLE FROM TESTS (config/credentials.yml.enc ships a
#   :test shopify config — see wart ledger). Every example that can reach a
#   Shopify edge stubs exactly the seam the code itself uses:
#   `LockerRental#checkout_link` (invoice-URL boundary used by the
#   await_payment show view).
# * Rails 8.1 maps `config.action_dispatch.show_exceptions = false` to
#   "resilient": raised app errors are turned into a 500 debug page instead of
#   re-raising in the test.

RSpec.describe "LockerRentals (HTTP contract)", type: :request do
  include ApplicationHelper # end_of_this_semester math used by the controller

  let(:owner) { create(:user, :regular_user) }
  let(:other) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }

  def log_in!(user, password: "asa32A353#")
    post login_authentication_path,
         params: { username_email: user.username, password: password }
    expect(response).to redirect_to(root_path)
    user
  end

  # Amendment C: mail is pinned by DELIVERED outcome (jobs performed), never
  # by enqueue mechanism, so moving mailer calls into jobs keeps this green.
  def deliveries
    ActionMailer::Base.deliveries
  end

  def expect_single_mail(to:, subject:)
    expect(deliveries.size).to eq(1)
    expect(deliveries.first.to).to eq([to])
    expect(deliveries.first.subject).to eq(subject)
  end

  def reviewing_rental!(tenant: owner)
    create(:locker_rental, :reviewing, rented_by: tenant)
  end

  before do
    LockerOption.where(
      name: [LockerOption::LOCKER_PRODUCT_LINK, LockerOption::LOCKERS_ENABLED]
    ).delete_all
    LockerOption.lockers_enabled = true
    CourseName.find_or_create_by!(name: "GNG1103")
    ActionMailer::Base.deliveries.clear
  end

  # ----------------------------------------------------------- auth gates

  describe "auth gates" do
    it "sends guests to login?back_to=... with NO flash on every locker_rentals action" do
      get locker_rentals_path
      expect(response).to redirect_to(login_path(back_to: "/locker_rentals"))
      expect(flash[:alert]).to be_nil

      get new_locker_rental_path
      expect(response).to redirect_to(login_path(back_to: "/locker_rentals/new"))

      rental = reviewing_rental!
      get locker_rental_path(rental)
      expect(response).to redirect_to(login_path(back_to: "/locker_rentals/#{rental.id}"))

      patch locker_rental_path(rental), params: { locker_rental: { state: "cancelled" } }
      expect(response)
        .to redirect_to(login_path)

      patch renew_locker_rental_path(rental)
      expect(response)
        .to redirect_to(login_path)

      get expired_locker_rentals_path
      expect(response)
        .to redirect_to(login_path(back_to: "/locker_rentals/expired"))

      get admin_locker_rentals_path
      expect(response)
        .to redirect_to(login_path(back_to: "/locker_rentals/admin"))

      get assign_locker_locker_rentals_path
      expect(response)
        .to redirect_to(login_path(back_to: "/locker_rentals/assign_locker"))

      patch toggle_contacted_locker_rental_path(rental)
      expect(response)
        .to redirect_to(login_path)
    end

    it "does not mutate anything for a guest create attempt" do
      expect do
        post locker_rentals_path,
             params: { locker_rental: { notes: "guest notes" } }
      end.not_to change(LockerRental, :count)
      expect(response).to redirect_to(login_path)
    end
  end

  # ------------------------------------------------------- GET index

  describe "GET /locker_rentals (index)" do
    before { log_in!(owner) }

    # N+1 pinned: see defects.md D-PERF11
    it "renders the CEED-lockers page with active rental cards AND the full history table", skip_bullet: true do
      active = create(:locker_rental, :active, rented_by: owner)
      cancelled = create(:locker_rental, rented_by: owner)
      cancelled.update!(decided_by: staff, state: :cancelled)

      get locker_rentals_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("lockers.all_locker_rentals"))
      expect(response.body).to include("CEED Lockers")
      expect(response.body).to include("Here you can see your locker rental history")

      # active rentals render a card each with the assigned locker specifier
      expect(response.body).to include("##{active.locker.specifier}")
      # history table lists every rental and hides staff columns. NOTE: this
      # table renders NO ids; pin state markers instead.
      expect(response.body).to include(I18n.t("lockers.your_locker_requests"))
      expect(response.body).to include('data-search="active"')
      expect(response.body).to include('data-search="cancelled"')
      expect(response.body).not_to include("Contacted")
    end

    it "offers the Request a locker link when no pending request exists" do
      get locker_rentals_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Request a locker")
      expect(response.body).to include('href="' + new_locker_rental_path + '"')
    end

    it "only ever shows the signed-in user's own rentals" do
      someone_else = create(:locker_rental, :active)
      get locker_rentals_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("##{someone_else.locker.specifier}")
      expect(response.body).not_to include("<td>#{someone_else.id}</td>")
    end
  end

  # ------------------------------------------------------- GET new

  describe "GET /locker_rentals/new" do
    it "renders the request form for a regular user with a fresh record" do
      log_in!(owner)
      get new_locker_rental_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Request a locker")
      expect(response.body).to include('name="locker_rental[requested_as]"')
      expect(response.body).to include('name="locker_rental[preferred_locker_id]"')
      expect(response.body).to include('name="locker_rental[notes]"')
      expect(response.body).to include("Submit request")
    end

    it "shows the audience-filtered available counts (a community user sees 'general' only)" do
      log_in!(owner)
      size = create(:locker_size)
      create(:locker, locker_size: size, audience: "gng")
      create(:locker, locker_size: size, audience: "general")

      get new_locker_rental_path
      tbody = response.body[/<tbody>.*<\/tbody>/m, 0]
      puts "COUNT ROW>>>#{tbody.split.join(' ')}<<<"
      expect(response).to have_http_status(:ok)
      expect(tbody).to match(
        %r{<td>\s*(?:<!--[^>]*-->\s*)?1\s*</td>\s*<td>#{Regexp.escape(size.size)}</td>}m
      )
    end

    it "uses the staff audience for staff viewers" do
      log_in!(staff)
      size = create(:locker_size)
      create(:locker, locker_size: size, audience: "staff")
      create(:locker, locker_size: size, audience: "general")

      get new_locker_rental_path
      tbody = response.body[/<tbody>.*<\/tbody>/m, 0]
      expect(response).to have_http_status(:ok)
      expect(tbody).to match(
        %r{<td>\s*(?:<!--[^>]*-->\s*)?1\s*</td>\s*<td>#{Regexp.escape(size.size)}</td>}m
      )
    end

    it "replaces the form with the pending notice once a request is under review" do
      pending_request = reviewing_rental!
      log_in!(owner)
      get new_locker_rental_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("You have a pending request for a locker")
      expect(response.body).to include('href="' + locker_rental_path(pending_request) + '"')
      expect(response.body).not_to include('name="locker_rental[notes]"')
    end

    it "replaces the form with the checkout notice for awaiting-payment requests" do
      rental = create(:locker_rental, :await_payment, rented_by: owner)

      log_in!(owner)
      get new_locker_rental_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your request has been accepted")
      expect(response.body).to include('href="' + locker_rental_path(rental) + '"')
    end

    it "says requests are not accepted when the sitewide switch is off" do
      LockerOption.lockers_enabled = false
      log_in!(owner)
      get new_locker_rental_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Locker requests are not currently accepted.")
      expect(response.body).not_to include('name="locker_rental[notes]"')
    end

    it "does not touch Shopify for the form (no persisted locker_product_link => nil product info)" do
      log_in!(owner)
      get new_locker_rental_path
      expect(response).to have_http_status(:ok)
      expect(LockerOption.locker_product_link).to be_nil
    end
  end

  # ------------------------------------------------------- POST create

  describe "POST /locker_rentals (create)" do
    context "as a regular user" do
      before { log_in!(owner) }

      it "creates a reviewing request for the signed-in user and enqueues the request mail" do
        expect do
          perform_enqueued_jobs do
            post locker_rentals_path,
                 params: { locker_rental: {
                   notes: "please a corner locker",
                   requested_as: "general"
                 } }
          end
        end.to change(LockerRental, :count).by(1)
        expect_single_mail(to: "ceed@uottawa.ca", subject: "New locker request")

        rental = LockerRental.order(:id).last
        expect(response).to redirect_to(new_locker_rental_path) # redirect_back fallback
        expect(rental.rented_by).to eq(owner)
        expect(rental.state).to eq("reviewing")
        expect(rental.owned_until).to be_nil
        expect(rental.locker).to be_nil
        expect(rental.notes).to eq("please a corner locker")
      end

      it "cannot reserve a locker or jump states: staff-only params are filtered out" do
        sneaky_user = create(:user)
        log_in!(sneaky_user)
        locker = create(:locker)

        expect do
          post locker_rentals_path,
               params: { locker_rental: {
                 notes: "try to sneak",
                 state: "active",
                 locker_id: locker.id
               } }
        end.to change(LockerRental, :count).by(1)
        rental = LockerRental.order(:id).last
        expect(rental.state).to eq("reviewing")
        expect(rental.locker_id).to be_nil
        expect(rental.rented_by).to eq(sneaky_user)
      end

      it "forces rented_by_id to the signed-in user (cannot request for someone else)" do
        expect do
          post locker_rentals_path,
               params: { locker_rental: { rented_by_id: other.id } }
        end.to change(LockerRental, :count).by(1)
        expect(LockerRental.order(:id).last.rented_by).to eq(owner)
      end

      it "redirects with the disabled alert and no record when lockers are disabled" do
        LockerOption.lockers_enabled = false

        expect do
          post locker_rentals_path, params: { locker_rental: { notes: "x" } }
        end.not_to change(LockerRental, :count)
        expect(response).to redirect_to(locker_rentals_path)
        expect(flash[:alert])
          .to eq("New locker rentals are not currently accepted.")
      end

      it "renders :new with 422 and the parked-error listing once one request already waits (the form is replaced by the blocked notice) — wart" do
        # WART(D-L15): 422 re-render shows blocked notice plus error list
        reviewing_rental! # one-request-per-user rule trips the 2nd POST

        log_in!(owner)
        expect do
          post locker_rentals_path, params: { locker_rental: { notes: "second" } }
        end.not_to change(LockerRental, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Errors:")
        expect(response.body)
          .to include("Rented by already has a request under review")
        # the pending notice replaced the form, so re-rendering :new shows it again
        expect(response.body).not_to include('name="locker_rental[notes]"')
      end

      it "validates the GNG student field bundle on create" do
        student = create(:user, :student)

        log_in!(student)
        expect do
          post locker_rentals_path,
               params: { locker_rental: {
                 requested_as: "student",
                 section_name: "A4"
               } }
        end.not_to change(LockerRental, :count)
        expect(response).to have_http_status(:unprocessable_content)

        post locker_rentals_path,
             params: { locker_rental: {
               requested_as: "student",
               section_name: "A4",
               team_name: "Team 1",
               course_name_id: CourseName.first.id
             } }
        expect(response).to redirect_to(new_locker_rental_path)
        rental = LockerRental.order(:id).last
        expect(rental.requested_as).to eq("student")
        expect(rental.state).to eq("reviewing")
      end
    end

    context "as staff (manual assignment flows)" do
      before { log_in!(staff) }

      it "assigns an ACTIVE rental directly: defaults owned_until to end of semester, sets decided_by, emails locker_assigned" do
        tenant = create(:user)
        locker = create(:locker)

        expect do
          perform_enqueued_jobs do
            post locker_rentals_path,
                 params: {
                   locker_rental: {
                     rented_by_id: tenant.id,
                     locker_id: locker.id,
                     state: "active"
                   }
                 }
          end
        end.to change(LockerRental, :count).by(1)
        expect_single_mail(
          to: tenant.email,
          subject: "Locker #{locker.specifier} has been assigned for you"
        )

        rental = LockerRental.order(:id).last
        expect(response).to redirect_to(new_locker_rental_path)
        expect(flash[:notice]).to eq("Locker assigned")
        expect(rental.state).to eq("active")
        expect(rental.rented_by).to eq(tenant)
        expect(rental.decided_by).to eq(staff)
        # controller defaulting: nil owned_until => end_of_this_semester
        expect(rental.owned_until.to_date).to eq(end_of_this_semester.to_date)
      end

      context "when the renter was deactivated after requesting" do
        let(:tenant) { create(:user) }
        let!(:rental) { create(:locker_rental, rented_by: tenant) }
        let(:locker) { create(:locker) }

        before { tenant.deactivate! }

        it "refuses activating or sending to payment (state-only PATCH), and leaves the rental reviewing" do
          %w[active await_payment].each do |state|
            patch locker_rental_path(rental), params: { locker_rental: { state: state, locker_id: locker.id } }
            expect(flash[:alert]).to include("Rented by is deactivated")
            expect(rental.reload.state).to eq("reviewing")
          end
          patch locker_rental_path(rental), params: { locker_rental: { state: "active" } }, as: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(rental.reload.state).to eq("reviewing")
        end

        it "still lets staff cancel it" do
          patch locker_rental_path(rental), params: { locker_rental: { state: "cancelled" } }
          expect(flash[:notice]).to eq("Locker rental updated")
          expect(rental.reload.state).to eq("cancelled")
        end

        it "refuses a PATCH naming an unknown renter username" do
          patch locker_rental_path(rental), params: { locker_rental: { rented_by_username: "nobody-here", notes: "x" } }
          expect(flash[:alert]).to include("User not found")
          expect(rental.reload.notes).not_to eq("x")
        end

        it "names a soft-deleted user by username as 'is deleted', not 'User not found'" do
          gone = create(:user)
          gone.update_columns(deleted: true)
          patch locker_rental_path(rental), params: { locker_rental: { rented_by_username: gone.username } }
          expect(flash[:alert]).to include("Rented by is deleted")
          expect(flash[:alert]).not_to include("User not found")
          expect(rental.reload.rented_by_id).to eq(tenant.id)
        end

        it "does not refuse an unknown username string when rented_by_id is sent: the id wins" do
          patch locker_rental_path(rental), params: { locker_rental: { rented_by_username: "nobody-here", rented_by_id: tenant.id, notes: "x" } }
          expect(flash[:alert]).to be_blank
          expect(rental.reload.notes).to eq("x")
        end

        it "refuses reassigning to a deactivated renter by id, with no state change" do
          other = create(:user)
          other.deactivate!
          patch locker_rental_path(rental), params: { locker_rental: { rented_by_id: other.id } }
          expect(flash[:alert]).to include("Rented by is deactivated")
          expect(rental.reload.rented_by_id).to eq(tenant.id)
        end
      end

      it "honors an explicit owned_until and lets indefinite ('1') clear the date" do
        post locker_rentals_path,
             params: { locker_rental: {
               rented_by_id: create(:user).id,
               locker_id: create(:locker).id,
               state: "active",
               owned_until: 3.days.from_now
             } }
        expect(LockerRental.order(:id).last.owned_until.to_date)
          .to eq(3.days.from_now.to_date)

        post locker_rentals_path,
             params: { locker_rental: {
               rented_by_id: create(:user).id,
               locker_id: create(:locker).id,
               state: "active",
               owned_until: 3.days.from_now,
               indefinite: "1"
             } }
        expect(LockerRental.order(:id).last.owned_until).to be_nil
      end

      it "sends to checkout: await_payment rentals keep their submitted owned_until and enqueue the checkout mail" do
        tenant = create(:user)
        locker = create(:locker)
        perform_enqueued_jobs do
          post locker_rentals_path,
               params: { locker_rental: {
                 rented_by_id: tenant.id,
                 locker_id: locker.id,
                 state: "await_payment",
                 owned_until: 3.days.from_now
               } }
        end
        expect_single_mail(
          to: tenant.email,
          subject: "Your locker rental for locker #{locker.specifier} is ready for checkout"
        )

        rental = LockerRental.order(:id).last
        expect(rental.state).to eq("await_payment")
        expect(rental.owned_until.to_date).to eq(3.days.from_now.to_date)
        # only ACTIVE assignment produces the "Locker assigned" notice
        expect(flash[:notice]).to be_nil
      end

      it "maps rented_by_username to the rental owner (search seam, FIXME in controller)" do
        tenant = create(:user)
        post locker_rentals_path,
             params: {
               locker_rental: {
                 locker_id: create(:locker).id,
                 state: "active",
                 rented_by_username: tenant.username
               }
             }
        expect(LockerRental.order(:id).last.rented_by).to eq(tenant)
        expect(response).to redirect_to(new_locker_rental_path)
      end

      it "rejects a second rental reserving the same locker with 422 (scope: await_payment|active)" do
        reserved = create(:locker_rental, :active)

        expect do
          post locker_rentals_path,
               params: { locker_rental: {
                 rented_by_id: create(:user).id,
                 locker_id: reserved.locker_id,
                 state: "active"
               } }
        end.not_to change(LockerRental, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Errors:")
        expect(response.body).to include("has already been taken")
      end

      it "ignores the disabled switch for staff entirely (|| short-circuit pins the wart)" do
        # WART(D-L13): staff bypass the sitewide lockers-disabled switch
        LockerOption.lockers_enabled = false
        expect do
          post locker_rentals_path,
               params: { locker_rental: {
                 rented_by_id: create(:user).id,
                 locker_id: create(:locker).id,
                 state: "active"
               } }
        end.to change(LockerRental, :count).by(1)
        expect(response).to redirect_to(new_locker_rental_path)
      end
    end

    context "as admin" do
      it "assigns exactly like staff (User#staff? includes role admin)" do
        log_in!(admin)
        post locker_rentals_path,
             params: { locker_rental: {
               rented_by_id: create(:user).id,
               locker_id: create(:locker).id,
               state: "active"
             } }
        expect(response).to redirect_to(new_locker_rental_path)
        expect(flash[:notice]).to eq("Locker assigned")
        expect(LockerRental.order(:id).last.state).to eq("active")
      end
    end
  end

  # ------------------------------------------------------- GET show

  describe "GET /locker_rentals/:id (show)" do
    it "allows the owner and renders the rental details page" do
      rental = reviewing_rental!
      log_in!(owner)

      get locker_rental_path(rental)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("lockers.locker_request"))
      expect(response.body).to include("##{rental.id}")
      expect(response.body).to include(owner.username)
      expect(response.body).to include("Back to My Lockers")
      expect(response.body).not_to include("Staff Internal Notes")
    end

    it "shows staff the whole audience supply in the locker picker and staff-only affordances" do
      gng_locker = create(:locker, audience: "gng")
      staff_locker = create(:locker, audience: "staff")
      general_locker = create(:locker, audience: "general")

      log_in!(staff)
      get locker_rental_path(reviewing_rental!)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(gng_locker.specifier)
      expect(response.body).to include(staff_locker.specifier)
      expect(response.body).to include(general_locker.specifier)
      expect(response.body).to include("Staff Internal Notes")
      expect(response.body).to include("Locker Inventory")
    end

    it "denies strangers with a plain redirect to the index (no flash set — wart)" do
      # WART(D-L14): stranger denial sets no flash
      rental = reviewing_rental!
      log_in!(other)

      get locker_rental_path(rental)
      expect(response).to redirect_to(locker_rentals_path)
      expect(flash[:alert]).to be_nil
    end

    it "returns 404 for an unknown rental id" do
      log_in!(owner)
      get locker_rental_path(id: 999_999_999)
      expect(response).to have_http_status(:not_found)
    end

    it "renders the renewal UI for an expired active rental and hides it when not renewable" do
      expired = create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago)
      fresh = create(:locker_rental, :active, rented_by: owner)

      log_in!(owner)
      get locker_rental_path(expired)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("lockers.rental_expired_at"))
      expect(response.body).to include("Renew Locker")
      expect(response.body).to include(renew_locker_rental_path(expired))

      get locker_rental_path(fresh)
      expect(response.body).not_to include("Renew Locker")
    end

    describe "for an await_payment rental (checkout CTA)" do
      before do
        # Shipped seam: show.html.erb dereferences LockerRental#checkout_link,
        # a Shopify draft-order invoice URL (network-backed; the committed
        # credentials make real network REACHABLE in this env). We stub the
        # model boundary exactly like the JobOrders chunk pins its pay page.
        allow_any_instance_of(LockerRental).to receive(:checkout_link)
          .and_return("https://checkout.example/invoice-1")
      end

      it "renders the Proceed to Checkout link from the checkout seam" do
        rental = create(:locker_rental, :await_payment, rented_by: owner)
        log_in!(owner)
        get locker_rental_path(rental)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Proceed to Checkout")
        expect(response.body).to include("https://checkout.example/invoice-1")
      end
    end

    describe "broken edges pinned as-is" do
      it "has no edit route (D-L10): 404" do
        rental = reviewing_rental!
        log_in!(owner)
        get "/locker_rentals/#{rental.id}/edit"

        expect(response).to have_http_status(:not_found)
        expect(LockerRental.exists?(rental.id)).to be(true)
      end

      it "has no destroy route (D-L11): DELETE answers 404 and nothing is destroyed" do
        rental = reviewing_rental!
        log_in!(admin)
        delete "/locker_rentals/#{rental.id}"

        expect(response).to have_http_status(:not_found)
        expect(LockerRental.exists?(rental.id)).to be(true) # nothing destroyed
      end
    end
  end

  # ------------------------------------------------------- PATCH update

  describe "PATCH /locker_rentals/:id (update)" do
    context "as staff acting on a reviewing request" do
      before do
        log_in!(staff)
        @locker = create(:locker)
      end

      it "approves to active: fills owned_until + decided_by, emails locker_assigned, redirects back with a notice" do
        rental = reviewing_rental!

        expect do
          perform_enqueued_jobs do
            patch locker_rental_path(rental),
                  params: { locker_rental: { state: "active", locker_id: @locker.id } }
          end
        end.to change { rental.reload.state }.from("reviewing").to("active")
        expect_single_mail(
          to: rental.rented_by.email,
          subject: "Locker #{@locker.specifier} has been assigned for you"
        )

        expect(response).to redirect_to(locker_rentals_path) # redirect_back fallback
        expect(flash[:notice]).to eq("Locker rental updated")
        expect(rental.reload.owned_until.to_date).to eq(end_of_this_semester.to_date)
        expect(rental.decided_by).to eq(staff)
      end

      it "routes reviewing → await_payment (checkout) with the checkout mail" do
        rental = reviewing_rental!

        expect do
          perform_enqueued_jobs do
            patch locker_rental_path(rental),
                  params: { locker_rental: { state: "await_payment", locker_id: @locker.id } }
          end
        end.to change { rental.reload.state }.from("reviewing").to("await_payment")
        expect_single_mail(
          to: rental.rented_by.email,
          subject: "Your locker rental for locker #{@locker.specifier} is ready for checkout"
        )
        expect(rental.reload.decided_by).to eq(staff)
      end

      it "cancels an ACTIVE rental (end rental) and enqueues the cancelled mail" do
        rental = create(:locker_rental, :active)

        expect do
          perform_enqueued_jobs do
            patch locker_rental_path(rental),
                  params: { locker_rental: { state: "cancelled" } }
          end
        end.to change { rental.reload.state }.from("active").to("cancelled")
        expect_single_mail(
          to: rental.rented_by.email,
          subject: "Your locker rental for locker #{rental.locker.specifier} has been cancelled"
        )
        expect(rental.reload.cancelled_at).to be_present
        expect(rental.reload.decided_by).to eq(staff)
      end

      it "moves an active rental's locker: only the move mail is delivered, no state-change mail" do
        rental = create(:locker_rental, :active)
        new_locker = create(:locker)

        perform_enqueued_jobs do
          patch locker_rental_path(rental),
                params: {
                  locker_rental: { state: "active", locker_id: new_locker.id }
                }
        end
        # a locker-only move sends the "modified" mail, never a second "assigned"
        expect_single_mail(
          to: rental.rented_by.email,
          subject: "Your locker rental for Locker #{new_locker.specifier} has been modified"
        )

        expect(response).to redirect_to(locker_rentals_path)
        expect(flash[:notice]).to eq("Locker rental updated")
        expect(rental.reload.locker_id).to eq(new_locker.id)
      end

      it "sends the move mail when BOTH locker and date change on an active rental" do
        rental = create(:locker_rental, :active, owned_until: 2.months.from_now)
        new_locker = create(:locker)

        perform_enqueued_jobs do
          patch locker_rental_path(rental),
                params: {
                  locker_rental: {
                    state: "active",
                    locker_id: new_locker.id,
                    owned_until: 40.days.from_now
                  }
                }
        end
        expect_single_mail(
          to: rental.rented_by.email,
          subject: "Your locker rental for Locker #{new_locker.specifier} has been modified"
        )
        expect(rental.reload.locker_id).to eq(new_locker.id)
      end

      it "collects validation failures into one redirect alert (HTML)" do
        rental = reviewing_rental!

        patch locker_rental_path(rental),
              params: { locker_rental: { state: "active", locker_id: "" } }

        expect(response).to redirect_to(locker_rentals_path)
        expect(flash[:alert]).to start_with("Failed to update locker rental")
        expect(flash[:alert]).to include("Locker This field is required.")
        expect(rental.reload.state).to eq("reviewing")
      end

      it "drives the indeifnite toggle for an active rental: owned_until -> nil in one request" do
        rental = create(:locker_rental, :active, owned_until: 1.month.from_now)
        new_locker = create(:locker)

        patch locker_rental_path(rental),
              params: { locker_rental: {
                state: :active,
                locker_id: new_locker.id,
                indefinite: "1"
              } }
        expect(rental.reload.owned_until).to be_nil
        expect(rental.locker_id).to eq(new_locker.id)
      end
    end

    context "as the owner of the rental" do
      it "lets a reviewing request be cancelled by its owner (decided_by becomes the owner)" do
        rental = reviewing_rental!(tenant: owner)
        log_in!(owner)

        expect do
          perform_enqueued_jobs do
            patch locker_rental_path(rental),
                  params: { locker_rental: { state: "cancelled" } }
          end
        end.to change { rental.reload.state }.from("reviewing").to("cancelled")
        expect_single_mail(
          to: owner.email,
          subject: "Your locker rental request has been cancelled"
        )

        expect(response).to redirect_to(locker_rentals_path)
        expect(rental.reload.cancelled_at).to be_present
        expect(rental.reload.decided_by).to eq(owner)
      end

      it "refuses an ACTIVE rental cancellation: alert + 422 re-render of :show (only staff end rentals)" do
        rental = create(:locker_rental, :active, rented_by: owner)
        log_in!(owner)

        patch locker_rental_path(rental),
              params: { locker_rental: { state: "cancelled" } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(I18n.t("lockers.locker_request")) # re-rendered :show view
        expect(flash[:alert])
          .to eq("Please contact administration for cancelling a locker")
        expect(rental.reload.state).to eq("active")
      end

      # Security: the only state changes a renter may make are reviewing -> cancelled and await_payment -> cancelled
      describe "a renter changing state on their own rental (self-activation)" do
        before { allow_any_instance_of(LockerRental).to receive(:checkout_link).and_return(nil) }

        %w[active await_payment reviewing cancelled].each do |target|
          it "refuses #{target} on a reviewing rental unless it is the cancellation (nothing saved, no mail, not settled)" do
            rental = reviewing_rental!(tenant: owner)
            rental.update_columns(locker_id: create(:locker).id)
            held = create(:locker_payment, :held, locker_rental: rental)
            log_in!(owner)
            ActionMailer::Base.deliveries.clear

            perform_enqueued_jobs do
              patch locker_rental_path(rental), params: { locker_rental: { state: target, locker_id: rental.locker_id } }
            end

            if target == "cancelled"
              expect(rental.reload.state).to eq("cancelled")
            elsif target == "reviewing"
              expect(rental.reload.state).to eq("reviewing") # no change
            else
              expect(response).to have_http_status(:unprocessable_content)
              expect(flash[:alert]).to eq("You can only cancel a pending request")
              expect(rental.reload.state).to eq("reviewing")
              expect(ActionMailer::Base.deliveries).to be_empty
            end
            expect(held.reload).to be_held
          end
        end

        it "refuses a renter moving an await_payment rental to active, and lets them cancel it" do
          rental = create(:locker_rental, :await_payment, rented_by: owner)
          log_in!(owner)
          patch locker_rental_path(rental), params: { locker_rental: { state: "active" } }
          expect(response).to have_http_status(:unprocessable_content)
          expect(rental.reload.state).to eq("await_payment")

          patch locker_rental_path(rental), params: { locker_rental: { state: "cancelled" } }, as: :json
          expect(response).to have_http_status(:no_content)
          expect(rental.reload.state).to eq("cancelled")
        end

        it "does not let a renter re-submitting state=active reset the term of an indefinite active rental" do
          rental = create(:locker_rental, :active, rented_by: owner, owned_until: nil, indefinite: "1")
          expect(rental.reload.owned_until).to be_nil
          log_in!(owner)
          patch locker_rental_path(rental), params: { locker_rental: { state: "active" } }
          expect(rental.reload.owned_until).to be_nil
          expect(rental.state).to eq("active")
        end

        it "refuses a renter re-activating a cancelled rental, or changing an active one to anything else" do
          cancelled = create(:locker_rental, :active, rented_by: owner).tap { |r| r.update!(state: :cancelled) }
          log_in!(owner)
          patch locker_rental_path(cancelled), params: { locker_rental: { state: "active" } }, as: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(cancelled.reload.state).to eq("cancelled")

          active = create(:locker_rental, :active, rented_by: owner)
          patch locker_rental_path(active), params: { locker_rental: { state: "await_payment" } }, as: :json
          expect(response).to have_http_status(:unprocessable_content)
          expect(active.reload.state).to eq("active")
        end
      end

      it "accepts only :state for owners (notes edits silently dropped — wart)" do
        # WART(D-L09): owner notes edits are silently dropped
        rental = reviewing_rental!(tenant: owner)
        log_in!(owner)

        patch locker_rental_path(rental),
              params: { locker_rental: { notes: "edited by owner!" } }

        expect(rental.reload.notes).not_to eq("edited by owner!")
        # and the same POST with cancelled state succeeds only through state
        patch locker_rental_path(rental),
              params: { locker_rental: { notes: "edited by owner!", state: "cancelled" } }
        expect(rental.reload.notes).not_to eq("edited by owner!")
        expect(rental.reload.state).to eq("cancelled")
      end

      it "redirects strangers without touching the rental" do
        rental = reviewing_rental!(tenant: owner)
        log_in!(other)

        patch locker_rental_path(rental),
              params: { locker_rental: { state: "cancelled" } }
        expect(response).to redirect_to(locker_rentals_path)
        expect(rental.reload.state).to eq("reviewing")
      end

      it "answers a JSON cancellation with 204 and no body" do
        rental = reviewing_rental!(tenant: owner)
        log_in!(owner)

        patch locker_rental_path(rental),
              params: { locker_rental: { state: "cancelled" } },
              as: :json

        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_blank
        expect(rental.reload.state).to eq("cancelled")
      end
    end

    describe "replay/regression warts pinned" do
      it "lets staff re-activate a cancelled rental (no guard anywhere — the only blocker is the hidden UI buttons)" do
        rental = create(:locker_rental, :active)
        rental.update!(decided_by: staff, state: :cancelled)
        log_in!(staff)

        patch locker_rental_path(rental),
              params: { locker_rental: { state: "active", locker_id: rental.locker_id } }

        expect(rental.reload.state).to eq("active")
      end
    end

    describe "Shopify sync boundary (cancel path)" do
      # SEAM: LockerRental#sync_shopify_draft_order_after_commit (called by the controller after commit) destroys the Shopify draft
      # order when state flips to :cancelled. On cancel, the concern calls
      # start_shopify_session then runs draftOrderDelete GraphQL. Because the
      # committed credentials make that call REAL network, we pin the
      # trigger contract at the seam level here and cover the GraphQL side in
      # the MODEL contract spec with a response-object stub.
      it "cancels a rental that never had a draft order (sync calls destroy... and it no-ops false)" do
        rental = create(:locker_rental, :active, shopify_draft_order_id: nil)
        log_in!(staff)

        # call_original preserves today's behavior: early return false, no HTTP
        expect_any_instance_of(LockerRental).to receive(:destroy_shopify_draft_order)
          .and_call_original

        patch locker_rental_path(rental),
              params: { locker_rental: { state: "cancelled" } }

        expect(response).to redirect_to(locker_rentals_path)
        expect(rental.reload.state).to eq("cancelled")
        expect(rental.shopify_draft_order_id).to be_nil
      end

      # The cancellation commits first; Shopify is called after, with no transaction open. A failure is reported
      # and shown to staff, the rental stays cancelled, the draft id is kept, and a late payment is held.
      it "cancels, reports and tells staff when deleting the draft order fails" do
        rental = create(:locker_rental, :active)
        rental.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/1")
        log_in!(staff)
        stub_request(:post, shopify_graphql_url).to_return(status: 500, body: "boom")
        allow(Rails.error).to receive(:report)

        patch locker_rental_path(rental), params: { locker_rental: { state: "cancelled" } }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to include("Shopify checkout could not be removed")
        expect(rental.reload.state).to eq("cancelled")
        expect(rental.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/1")
        expect(Rails.error).to have_received(:report).once
      end

      it "subscriber fires only on a saved state change (no mail/sync on unrelated updates)" do
        rental = create(:locker_rental, :active)
        log_in!(staff)

        expect_any_instance_of(LockerRental).not_to receive(:destroy_shopify_draft_order)

        patch locker_rental_path(rental),
              params: { locker_rental: { owned_until: 50.days.from_now } }

        expect(response).to redirect_to(locker_rentals_path)
        expect(rental.state).to eq("active")
      end
    end
  end

  # ------------------------------------------------------- PATCH renew

  describe "PATCH /locker_rentals/:id/renew" do
    it "moves an expired ACTIVE rental into await_payment with the end-of-semester date" do
      rental = create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago)
      log_in!(owner)

      patch renew_locker_rental_path(rental)

      expect(response).to redirect_to(locker_rental_path(rental))
      expect(flash[:notice])
        .to eq("Locker renewal started. Please complete checkout to renew your locker.")
      expect(rental.reload.state).to eq("await_payment")
      expect(rental.reload.owned_until.to_date).to eq(end_of_this_semester.to_date)
      expect(rental.reload.decided_by).to eq(owner)
    end

    it "refuses renewal of a NOT expired rental with the alert redirect" do
      rental = create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.from_now)
      log_in!(owner)

      patch renew_locker_rental_path(rental)

      expect(response).to redirect_to(locker_rental_path(rental))
      expect(flash[:alert]).to eq("This locker rental is not renewable.")
      expect(rental.reload.state).to eq("active")
    end

    it "refuses renewal of an indefinite (nil date) active rental — expired? is nil for nil dates" do
      rental = create(:locker_rental, :active, rented_by: owner)
      rental.update_columns(owned_until: nil) # factory assigns a date; indefinite rentals store none
      log_in!(owner)

      patch renew_locker_rental_path(rental)
      expect(response).to redirect_to(locker_rental_path(rental))
      expect(flash[:alert]).to eq("This locker rental is not renewable.")
      expect(rental.reload.state).to eq("active")
    end

    it "redirects strangers away from renewal" do
      rental = create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago)
      log_in!(other)

      patch renew_locker_rental_path(rental)
      expect(response).to redirect_to(locker_rentals_path)
      expect(rental.reload.state).to eq("active")
    end

    it "staff can renew somebody else's expired rental" do
      rental = create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago)
      log_in!(staff)

      patch renew_locker_rental_path(rental)
      expect(response).to redirect_to(locker_rental_path(rental))
      expect(rental.reload.state).to eq("await_payment")
      expect(rental.reload.decided_by).to eq(staff)
    end
  end

  # ------------------------------------------------------- GET admin

  describe "held payments (staff)" do
    let(:tenant) { create(:user) }
    let!(:rental) { create(:locker_rental, :await_payment, rented_by: tenant) }

    # an await_payment page would fetch the checkout link from Shopify; not under test here
    before { allow_any_instance_of(LockerRental).to receive(:checkout_link).and_return(nil) }

    # the badge markup itself: the section heading carries the same words
    let(:badge) { %(<span class="badge text-bg-danger mt-1">#{I18n.t('lockers.held_payments.badge')}</span>) }

    def hold!(rental, reason: "renter_ineligible", id: nil)
      create(:locker_payment, :held, locker_rental: rental, hold_reason: reason, **(id ? { shopify_order_id: id } : {}))
    end

    it "shows the badge, the section and the alert only while a held payment exists, driven by the scope" do
      log_in!(staff)
      get admin_locker_rentals_path
      expect(response.body).not_to include(badge)
      expect(response.body).to include(I18n.t("lockers.held_payments.none"))

      payment = hold!(rental)
      get admin_locker_rentals_path
      expect(response.body).to include(badge)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("lockers.held_payments.reasons.renter_ineligible")))
      get locker_rental_path(rental)
      expect(response.body).to include(I18n.t("lockers.held_payments.alert_title"))
      expect(response.body).to include(payment.shopify_order_id)

      payment.resolve!("dismissed", by: staff)
      get admin_locker_rentals_path
      expect(response.body).not_to include(badge)
      get locker_rental_path(rental)
      expect(response.body).not_to include(I18n.t("lockers.held_payments.alert_title"))
    end

    it "does not derive anything from paid_at: a renewal in await_payment with an old paid_at shows no badge" do
      rental.update_columns(paid_at: 6.months.ago)
      tenant.deactivate!
      log_in!(staff)
      get admin_locker_rentals_path
      expect(response.body).not_to include(badge)
      get locker_rental_path(rental)
      expect(response.body).not_to include(I18n.t("lockers.held_payments.alert_title"))
    end

    it "lists held rentals including a cancelled one, in the Paid, needs a decision section" do
      cancelled = create(:locker_rental, :active)
      cancelled.update!(state: :cancelled)
      hold!(cancelled, reason: "rental_cancelled")
      log_in!(staff)
      get admin_locker_rentals_path
      expect(response.body).to include(I18n.t("lockers.held_payments.title"))
      expect(response.body).to include(cancelled.rented_by.username)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("lockers.held_payments.reasons.rental_cancelled")))
    end

    it "chooses the instruction by rental state: never 'assign the locker' for a payment held on an ACTIVE rental" do
      active = create(:locker_rental, :active)
      hold!(active)
      awaiting = create(:locker_rental, :await_payment)
      hold!(awaiting)
      log_in!(staff)
      get locker_rental_path(active)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("lockers.held_payments.reasons.renter_ineligible_active")))
      expect(response.body).not_to include(CGI.escapeHTML(I18n.t("lockers.held_payments.reasons.renter_ineligible")))
      get locker_rental_path(awaiting)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("lockers.held_payments.reasons.renter_ineligible")))
    end

    it "shows the duplicate wording for an already_paid hold" do
      active = create(:locker_rental, :active)
      hold!(active, reason: "already_paid")
      log_in!(staff)
      get locker_rental_path(active)
      expect(response.body).to include(I18n.t("lockers.held_payments.reasons.already_paid"))
    end

    it "keeps the badge when the renter is reactivated" do
      tenant.deactivate!
      hold!(rental)
      tenant.reactivate!
      log_in!(staff)
      get admin_locker_rentals_path
      expect(response.body).to include(badge)
    end

    it "cancelling the rental does not resolve the payment" do
      hold!(rental)
      log_in!(staff)
      patch locker_rental_path(rental), params: { locker_rental: { state: "cancelled" } }
      expect(rental.reload.state).to eq("cancelled")
      get admin_locker_rentals_path
      expect(response.body).to include(badge)
      expect(rental.locker_payments.sole).to be_held
    end

    it "shows the payment history to staff only" do
      payment = hold!(rental)
      log_in!(tenant)
      get locker_rental_path(rental)
      expect(response.body).not_to include(payment.shopify_order_id)
      expect(response.body).not_to include(I18n.t("lockers.held_payments.alert_title"))
    end

    it "does not show the renter Paid on for a cancelled rental whose payment was held" do
      cancelled = create(:locker_rental, :active, rented_by: tenant).tap { |x| x.update!(state: :cancelled) }
      cancelled.record_payment(shopify_order_id: "late-1")
      log_in!(tenant)
      get locker_rental_path(cancelled)
      expect(response.body).not_to include(I18n.t("lockers.paid_on"))
      expect(response.body).to include(I18n.t("lockers.unpaid"))
    end

    it "keeps showing the hold reason and resolution of a resolved payment as history" do
      payment = hold!(rental)
      payment.resolve!("refunded", by: staff, note: "done in Shopify")
      log_in!(staff)
      get locker_rental_path(rental)
      expect(response.body).to include(I18n.t("lockers.held_payments.statuses.refunded"))
      expect(response.body).to include("done in Shopify")
      # history is neutral: no instruction ("Refund the payment, or...") once it is resolved
      expect(response.body).to include(I18n.t("lockers.held_payments.was_held", reason: I18n.t("lockers.held_payments.past_reasons.renter_ineligible")))
      expect(response.body).not_to include(CGI.escapeHTML(I18n.t("lockers.held_payments.reasons.renter_ineligible")))
      expect(response.body).not_to include(I18n.t("lockers.held_payments.alert_title"))
    end

    it "shows 'Paid (legacy)' for a rental with a paid_at and no payment rows" do
      rental.update_columns(paid_at: Time.utc(2026, 5, 20))
      log_in!(staff)
      get locker_rental_path(rental)
      expect(response.body).to include(I18n.t("lockers.held_payments.legacy_paid"))
    end

    describe "assigning the rental active (Assign now)" do
      it "applies ONE held payment (the oldest curable) in the same update; the others, even a duplicate, stay held" do
        reviewing = create(:locker_rental, :reviewing)
        newer = hold!(reviewing, reason: "not_activatable")
        newer.update_columns(paid_at: 1.day.ago)
        older = hold!(reviewing)
        older.update_columns(paid_at: 2.days.ago)
        cancelled = hold!(reviewing, reason: "rental_cancelled")
        locker = create(:locker)
        log_in!(staff)
        patch locker_rental_path(reviewing), params: { expected_state: "reviewing", locker_rental: { state: "active", locker_id: locker.id } }
        expect(reviewing.reload.state).to eq("active")
        expect([older, newer, cancelled].map { |x| x.reload.status }).to eq(%w[applied held held])
        expect(older.resolved_by).to eq(staff)
        expect(reviewing.paid_at).to be_within(1.second).of(older.paid_at)
      end

      it "refuses an assignment made from a stale page (expected_state no longer matches): nothing changes" do
        reviewing = create(:locker_rental, :await_payment)
        payment = hold!(reviewing)
        log_in!(staff)
        patch locker_rental_path(reviewing), params: { expected_state: "reviewing", locker_rental: { state: "active" } }
        expect(flash[:alert]).to include("changed while you had the page open")
        expect(reviewing.reload.state).to eq("await_payment")
        expect(payment.reload).to be_held
      end

      it "leaves the payment held when the assignment fails (renter still deactivated)" do
        tenant.deactivate!
        payment = hold!(rental)
        log_in!(staff)
        patch locker_rental_path(rental), params: { locker_rental: { state: "active", locker_id: rental.locker_id } }
        expect(flash[:alert]).to include("Rented by is deactivated")
        expect(rental.reload.state).to eq("await_payment")
        expect(payment.reload).to be_held
      end

      it "settles nothing for a plain note edit" do
        payment = hold!(create(:locker_rental, :active))
        log_in!(staff)
        patch locker_rental_path(payment.locker_rental), params: { locker_rental: { staff_notes: "x" } }
        expect(payment.reload).to be_held
      end
    end
  end

  describe "PATCH /locker_rentals/:id/locker_payments/:id (resolve a held payment)" do
    let!(:payment) { create(:locker_payment, :held) }
    let(:rental) { payment.locker_rental }
    let(:path) { locker_rental_locker_payment_path(rental, payment) }

    it "lets staff mark it refunded, with a note, and records who and when" do
      log_in!(staff)
      patch path, params: { resolution: "refunded", resolution_note: "refunded in Shopify" }
      expect(response).to redirect_to(locker_rental_path(rental))
      expect(payment.reload).to have_attributes(status: "refunded", resolved_by_id: staff.id, resolution_note: "refunded in Shopify", hold_reason: "renter_ineligible")
      expect(payment.resolved_at).to be_present
      expect(LockerRental.with_held_payment).to be_empty
    end

    it "lets staff dismiss it" do
      log_in!(staff)
      patch path, params: { resolution: "dismissed" }
      expect(payment.reload.status).to eq("dismissed")
    end

    it "refuses an unknown resolution, and an already resolved payment" do
      log_in!(staff)
      patch path, params: { resolution: "bogus" }
      expect(payment.reload).to be_held
      patch path, params: { resolution: "refunded" }
      patch path, params: { resolution: "dismissed" }
      expect(payment.reload.status).to eq("refunded")
      expect(flash[:alert]).to eq(I18n.t("lockers.held_payments.already_resolved"))
    end

    it "is staff only: the renter and a non-staff user get 403 and nothing changes" do
      [rental.rented_by, create(:user, :regular_user)].each do |user|
        log_in!(user)
        patch path, params: { resolution: "refunded" }
        expect(response).to have_http_status(:forbidden)
      end
      expect(payment.reload).to be_held
    end

    it "has no staff 'applied' resolution: it is refused as invalid and the payment stays held (a duplicate must stay visible)" do
      active_rental_payment = create(:locker_payment, :held, locker_rental: create(:locker_rental, :active))
      log_in!(staff)
      patch locker_rental_locker_payment_path(active_rental_payment.locker_rental, active_rental_payment),
            params: { resolution: "applied" }
      expect(flash[:alert]).to eq(I18n.t("lockers.held_payments.invalid_resolution"))
      expect(active_rental_payment.reload).to be_held
      expect(response.body).not_to include("Mark applied")
    end

    it "lets staff dismiss, with a note, a payment that arrived after the assignment" do
      late = create(:locker_payment, :held, locker_rental: create(:locker_rental, :active))
      log_in!(staff)
      patch locker_rental_locker_payment_path(late.locker_rental, late), params: { resolution: "dismissed", resolution_note: "paid after assign" }
      expect(late.reload).to have_attributes(status: "dismissed", resolution_note: "paid after assign")
    end

    it "does not find a payment through another rental" do
      other = create(:locker_rental, :active)
      log_in!(staff)
      patch locker_rental_locker_payment_path(other, payment), params: { resolution: "refunded" }
      expect(response).to have_http_status(:not_found)
      expect(payment.reload).to be_held
    end

    it "redirects a signed-out visitor to login" do
      patch path, params: { resolution: "refunded" }
      expect(response).to have_http_status(:redirect)
      expect(payment.reload).to be_held
    end
  end

  describe "GET /locker_rentals/admin" do
    it "splits pending reviewing requests from dealt-with (await_payment/active) rentals for staff" do
      reviewing = create(:locker_rental, :reviewing)
      awaiting = create(:locker_rental, :await_payment)
      active = create(:locker_rental, :active)
      cancelled = create(:locker_rental, :active)
      cancelled.update!(decided_by: staff, state: :cancelled)

      log_in!(staff)
      get admin_locker_rentals_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Locker Rentals")
      expect(response.body).to include("Requests")
      expect(response.body).to include(locker_rental_path(reviewing))
      expect(response.body).to include(locker_rental_path(active))
      expect(response.body).to include(locker_rental_path(awaiting))
      expect(response.body).not_to include(locker_rental_path(cancelled))
      expect(response.body).to include("Contacted")
      expect(response.body)
        .to include(toggle_contacted_locker_rental_path(awaiting))
    end

    it "is staff/admin-only for HTML (regular users bounce with no flash)" do
      log_in!(owner)
      get admin_locker_rentals_path
      expect(response).to redirect_to(locker_rentals_path)
      expect(flash[:alert]).to be_nil
    end

    # N+1 pinned: see defects.md D-PERF12
    it "serves JSON with pending/active keys (no eager-serialized association payloads)", skip_bullet: true do
      tenant = create(:locker_rental, :reviewing)
      awaiting = create(:locker_rental, :await_payment)

      log_in!(staff)
      get admin_locker_rentals_path, as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["pending"].map { |r| r["id"] }).to include(tenant.id)
      expect(json["active"].map { |r| r["id"] }).to include(awaiting.id)
      expect(json["pending"].first.keys).to include("state", "rented_by_id", "notes")
      expect(json["pending"].first).not_to have_key("locker")
      expect(json["pending"].first).not_to have_key("rented_by")
    end

    it "renders a pending request whose owner was soft-deleted (the association is unscoped from User's default scope)" do
      tenant = create(:user)
      create(:locker_rental, :reviewing, rented_by: tenant)
      tenant.update_columns(deleted: true)

      log_in!(staff)
      get admin_locker_rentals_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(tenant.username)
    end
  end

  # ------------------------------------------------------- GET expired

  describe "GET /locker_rentals/expired" do
    it "lists overdue active rentals for staff" do
      expired_rental = create(:locker_rental, :active, owned_until: 1.week.ago)
      log_in!(staff)

      get expired_locker_rentals_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Expired locker rentals")
      expect(response.body).to include(expired_rental.locker.specifier)
      expect(response.body).to include(expired_rental.rented_by.username)
      expect(response.body).to include('href="' + locker_rental_path(expired_rental) + '"')
    end

    it "bounces regular users even if they own the expired rental" do
      create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago)
      log_in!(owner)

      get expired_locker_rentals_path
      expect(response).to redirect_to(locker_rentals_path)
    end

    it "renders an empty table for staff when nothing is expired (the 'no expired' paragraph can never render — wart)" do
      # WART(D-L12): the "no expired" paragraph can never render
      log_in!(staff)
      get expired_locker_rentals_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Expired locker rentals")
      expect(response.body).not_to include("There are no expired lockers")
    end
  end

  # --------------------------------------------------- GET assign_locker

  describe "GET /locker_rentals/assign_locker" do
    it "shows the staff assignment form posting to the create endpoint" do
      log_in!(staff)
      get assign_locker_locker_rentals_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Assign locker to a user")
      expect(response.body).to include('action="' + locker_rentals_path + '"')
      expect(response.body).to include('value="active"', 'value="staff"')
    end

    it "lists users who are not deactivated (including legacy active = false) and not deactivated ones" do
      legacy = create(:user, :regular_user, username: "legacydormant")
      User.where(id: legacy.id).update_all(active: false)
      gone = create(:user, :regular_user, username: "deactivatedone")
      gone.deactivate!
      log_in!(staff)
      get assign_locker_locker_rentals_path

      expect(response.body).to include("legacydormant")
      expect(response.body).not_to include("deactivatedone")
    end

    it "bounces regular users" do
      log_in!(owner)
      get assign_locker_locker_rentals_path
      expect(response).to redirect_to(locker_rentals_path)
    end
  end

  # ------------------------------------------------ PATCH toggle_contacted

  describe "PATCH /locker_rentals/:id/toggle_contacted" do
    it "toggles contacted_for_clearance for staff via update_column (204, no body)" do
      rental = create(:locker_rental, :active, contacted_for_clearance: false)
      log_in!(staff)

      patch toggle_contacted_locker_rental_path(rental)

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
      expect(rental.reload.contacted_for_clearance).to eq(true)

      patch toggle_contacted_locker_rental_path(rental)
      expect(rental.reload.contacted_for_clearance).to eq(false)
    end

    it "is forbidden for owners that are not staff (403, unchanged)" do
      rental = create(:locker_rental, :active, rented_by: owner)
      log_in!(owner)

      patch toggle_contacted_locker_rental_path(rental)

      expect(response).to have_http_status(:forbidden)
      expect(rental.reload.contacted_for_clearance).to eq(false)
    end

    it "redirects strangers through check_permission BEFORE the staff gate" do
      rental = create(:locker_rental, :active, rented_by: owner)
      log_in!(other)

      patch toggle_contacted_locker_rental_path(rental)

      expect(response).to redirect_to(locker_rentals_path)
      expect(rental.reload.contacted_for_clearance).to eq(false)
    end

    it "runs as a raw update_column: validations and state callbacks do not participate" do
      rental = create(:locker_rental, :active)
      log_in!(staff)

      patch toggle_contacted_locker_rental_path(rental)
      expect(rental.reload.contacted_for_clearance).to eq(true)
      expect(rental.reload.state).to eq("active")
    end
  end
  # ------------------------------------------------ delivered-mail outcomes

  describe "mail outcomes for non-transitions and renewal (delivered, not enqueued)" do
    it "delivers nothing when a validation failure blocks the update" do
      log_in!(staff)
      rental = reviewing_rental!
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs do
        patch locker_rental_path(rental),
              params: { locker_rental: { state: "active", locker_id: "" } }
      end
      expect(deliveries).to be_empty
    end

    it "delivers nothing when an owner is refused cancelling an active rental" do
      rental = create(:locker_rental, :active, rented_by: owner)
      log_in!(owner)
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs do
        patch locker_rental_path(rental), params: { locker_rental: { state: "cancelled" } }
      end
      expect(deliveries).to be_empty
    end

    it "delivers nothing for a stranger's update attempt or a plain notes edit by staff" do
      rental = create(:locker_rental, :active, rented_by: owner)
      log_in!(other)
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs do
        patch locker_rental_path(rental), params: { locker_rental: { state: "cancelled" } }
      end
      expect(deliveries).to be_empty

      log_in!(staff)
      perform_enqueued_jobs do
        patch locker_rental_path(rental), params: { locker_rental: { staff_notes: "hello" } }
      end
      expect(deliveries).to be_empty
    end

    it "renewal (expired active -> await_payment) delivers the checkout mail" do
      rental = create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago)
      log_in!(owner)
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs { patch renew_locker_rental_path(rental) }
      expect_single_mail(
        to: owner.email,
        subject: "Your locker rental for locker #{rental.locker.specifier} is ready for checkout"
      )
    end

    it "a refused (non-renewable) renewal delivers nothing" do
      rental = create(:locker_rental, :active, rented_by: owner)
      log_in!(owner)
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs { patch renew_locker_rental_path(rental) }
      expect(deliveries).to be_empty
    end

    it "cancelling an await_payment rental by staff delivers the cancelled mail and destroys the draft order" do
      rental = create(:locker_rental, :await_payment, rented_by: owner)
      log_in!(staff)
      ActionMailer::Base.deliveries.clear
      expect_any_instance_of(LockerRental).to receive(:destroy_shopify_draft_order).once
      perform_enqueued_jobs do
        patch locker_rental_path(rental), params: { locker_rental: { state: "cancelled" } }
      end
      expect_single_mail(
        to: owner.email,
        subject: "Your locker rental for locker #{rental.locker.specifier} has been cancelled"
      )
    end
  end
end
