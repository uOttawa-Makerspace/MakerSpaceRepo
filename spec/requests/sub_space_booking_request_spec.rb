# frozen_string_literal: true

require "rails_helper"

# Characterization spec for SubSpaceBookingController (HTTP contract).
#
# Pins CURRENT observable behavior in the devcontainer test env:
#  - real login POST (the shipped sign_in_via_session shim doesn't work for
#    type: :request — see spec/support/auth_helpers.rb + repositories.rb:3)
#  - BookingStatus::PENDING/APPROVED/DECLINED are nil when the app boots
#    (BookingStatus.rb finds rows at boot; test DB is empty) → each example
#    creates rows and stubs the constants, mirroring
#    spec/controllers/subspace_bookings_controller_spec.rb.
#  - Raw wall-time storage: the column is `timestamp without time zone`. The
#    model string/DateTime-cast rounds by the TEST DB's default (UTC), while
#    the controller creates bookings with raw string params. Values are
#    pinned via raw SQL (::text) to avoid TZ re-normalization.
#  - Known warts are PINNED, not fixed (see doc/architecture.md §5.3.1 plan).

RSpec.describe "Sub Space Bookings (HTTP contract)", type: :request do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
  end

  # ---------------------------------------------------------------- helpers

  # Real login (sessions_controller#authenticate). Rate limiting uses the
  # default :null_store in tests, so logins are never throttled here.
  def log_in!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
    follow_redirect!
  end

  def status_name(booking)
    booking.reload.sub_space_booking_status.booking_status.name
  end

  # Raw wall clock stored in Postgres for `timestamp without time zone`.
  # DateTime.parse(...).change(offset: 0) → the literal wall hits the DB
  # unchanged (offset 0 == UTC), so factory-built rows store the literal.
  def raw_utc_wall(booking, column = "start_time")
    ActiveRecord::Base.connection.select_value(
      "SELECT #{column}::text FROM sub_space_bookings WHERE id = #{booking.id}"
    )
  end

  # Booking factory hooks a Pending status row after create; override it.
  def set_booking_status!(booking, status_row)
    booking.sub_space_booking_status
           .update!(booking_status_id: status_row.id)
    booking
  end

  # ------------------------------------------------------- auth gate matrix

  describe "auth gates" do
    it "bounces guests to the login page on index" do
      get sub_space_booking_index_path
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq("You must be logged in to view this page.")
    end

    it "bounces guests on the bookings feed" do
      get bookings_sub_space_booking_index_path, params: { room: "1" }
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq("You must be logged in to view this page.")
    end

    it "bounces guests on the admin-ish endpoints (users)" do
      # WART(D-B24): current_user is ALWAYS a (blank) User instance for guests
      # (ApplicationHelper#current_user falls back to User.new), so the
      # user_account gate never fires; guests land on user_admin_or_staff.
      get users_sub_space_booking_index_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert])
        .to eq("You must be an admin or staff to view this page.")
    end

    it "bounces guests hitting create on user_approved" do
      post sub_space_booking_index_path, params: { sub_space_booking: { name: "x" } }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert])
        .to eq("You must be approved to book to view this page.")
      expect(SubSpaceBooking.where(name: "x")).to be_empty
    end

    it "lets an unapproved user VIEW the index page but not create" do
      # WART(D-B25): user_approved only gates #create — an unapproved user sees the
      # index with the "Request Booking Access" panel instead of the tabs.
      user = create(:user, :regular_user, booking_approval: false)
      log_in!(user)

      get sub_space_booking_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Request Booking Access")
      expect(response.body).not_to include("Book Room")

      subspace = create(:sub_space)
      post sub_space_booking_index_path, params: { sub_space_booking: {
        sub_space_id: subspace.id, start_time: "2027-03-03 10:00",
        end_time: "2027-03-03 11:00", name: "N", description: "D"
      } }
      expect(flash[:alert])
        .to eq("You must be approved to book to view this page.")
      expect(SubSpaceBooking.where(name: "N")).to be_empty
    end

    it "lets an unapproved user still hit the bookings feed + request access" do
      user = create(:user, :regular_user, booking_approval: false)
      log_in!(user)

      get bookings_sub_space_booking_index_path, params: { room: "x" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])

      put request_access_sub_space_booking_index_path,
          params: { comments: "reason", identity: "Other" }
      expect(flash[:notice]).to eq("Access request submitted successfully.")
    end
  end

  # -------------------------------------------------------- create (JSON)

  describe "POST create (json)" do
    let(:user) { create(:user, :regular_user, booking_approval: true) }
    let(:space) { create(:space) }
    let(:subspace) { create(:sub_space, space: space) }

    before { log_in!(user) }

    def json_create(extra = {})
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-03-03 10:00",
             end_time: "2027-03-03 11:00", name: "Fresh", description: "Desc"
           }.merge(extra) }
    end

    it "returns 204 with an empty body and persists an auto-approved booking" do
      json_create
      expect(response.status).to eq(204)
      expect(response.body).to eq("")
      booking = SubSpaceBooking.find_by!(name: "Fresh")
      expect(booking.description).to eq("Desc")
      expect(booking.sub_space_id).to eq(subspace.id)
      expect(booking.blocking).to be(false)
      expect(raw_utc_wall(booking)).to eq("2027-03-03 15:00:00")
      expect(raw_utc_wall(booking, "end_time")).to eq("2027-03-03 16:00:00")
      expect(status_name(booking)).to eq("Approved")
      expect(booking.user_id).to eq(user.id)
      expect(booking.public).to be(false) # subspace default_public default
      expect(booking.approved_at).to be_nil # only admin bookings are stamped
      expect(booking.approved_by_id).to be_nil
    end

    it "marks pending subspace bookings as Pending and emails the space managers" do
      staffed_space = create(:space, :with_space_managers)
      ActionMailer::Base.deliveries.clear
      req = create(:sub_space, space: staffed_space, approval_required: true,
                               max_automatic_approval_hour: nil)
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: req.id, start_time: "2027-03-03 10:00",
             end_time: "2027-03-03 11:00", name: "N", description: "D"
           } }
      expect(response.status).to eq(204)
      expect(SubSpaceBooking.find_by(name: "N").sub_space_booking_status
              .booking_status.name).to eq("Pending")
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq("Booking needs approval")
      expect(mail.to).to match_array(staffed_space.space_managers.map(&:email))
    end

    it "requires name/description/start/end with the app's i18n full messages" do
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: { sub_space_id: subspace.id } }
      expect(response.status).to eq(422)
      expect(response.parsed_body).to eq(
        "errors" => [
          "Name This field is required.",
          "Description This field is required.",
          "Start time This field is required.",
          "End time This field is required."
        ]
      )
    end

    # WART(D-B21): the time-order error is attached to :expiration_date
    it "rejects end_time <= start_time" do
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-03-03 10:00",
             end_time: "2027-03-03 10:00", name: "N", description: "D"
           } }
      expect(response.status).to eq(422)
      expect(response.parsed_body)
        .to eq("errors" =>
               ["Expiration date Start Time needs to be before end time"])
    end

    it "needs a real sub space" do
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             start_time: "2027-03-03 10:00", end_time: "2027-03-03 11:00",
             name: "N", description: "D"
           } }
      expect(response.status).to eq(422)
      expect(response.parsed_body)
        .to eq("errors" => ["Sub space must exist"])
    end

    it "rejects a non-admin booking longer than maximum_booking_duration" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 4)
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: capped.id, start_time: "2027-03-03 10:00",
             end_time: "2027-03-03 15:00", name: "TooLong", description: "D"
           } }
      expect(response.status).to eq(422)
      expect(response.parsed_body).to eq(
        "errors" =>
          ["DurationHour You cannot book #{capped.name} for more than 4 hours."]
      )
      expect(SubSpaceBooking.where(name: "TooLong")).to be_empty
    end

    it "lets an admin book longer than maximum_booking_duration" do
      capped = create(:sub_space, space: space, maximum_booking_duration: 4)
      admin = create(:user, :admin, booking_approval: true)
      log_in!(admin)
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: capped.id, start_time: "2027-03-03 10:00",
             end_time: "2027-03-03 15:00", name: "AdminLong", description: "D"
           } }
      expect(response.status).to eq(204)
      expect(SubSpaceBooking.find_by!(name: "AdminLong").sub_space_id)
        .to eq(capped.id)
    end

    # WART(D-B05) (sub_space_booking_controller.rb:391): the weekly quota
    # computes `existing_total - new_duration` (total_duration starts at
    # `- duration` and the new booking is included in the user_bookings
    # window), so the cap only bites when existing > cap + new.
    # Pinned to a fixed Wednesday midday (Eastern) so the controller's
    # server-zone `DateTime.now.beginning_of_week` window always contains both
    # bookings, whatever time the suite runs. The login happens inside the
    # travel block because the session expires 72h after sign-in.
    it "applies the backwards weekly-quota computation" do
      travel_to(Time.zone.local(2027, 3, 10, 12, 0)) do
        log_in!(user)
        capped = create(:sub_space, space: space,
                                    maximum_booking_hours_per_week: 2)
        existing = 4.hours.ago.to_datetime
        create(:sub_space_booking, sub_space: capped, user: user,
               name: "Earlier", start_time: existing, end_time: existing + 4.hours)
        post sub_space_booking_index_path, as: :json,
             params: { sub_space_booking: {
               sub_space_id: capped.id,
               start_time: "2027-03-10 13:00",
               end_time: "2027-03-10 14:00",
               name: "OverWeek", description: "D"
             } }
        expect(response.status).to eq(422)
        expect(response.parsed_body).to eq(
          "errors" =>
            ["DurationWeek You cannot book #{capped.name} for more than 2 hours per week."]
        )
        expect(SubSpaceBooking.where(name: "OverWeek")).to be_empty
        expect(SubSpaceBooking.where(user_id: user.id).pluck(:name))
          .to eq(["Earlier"])
      end
    end

    it "stores string params shifted to the Eastern DST offset in UTC" do
      # WART(D-B06): controller create parses the string by the app zone (March →
      # EST = -05:00 → UTC wall 15:00) while the overlap binds use the
      # literal wall. Factory rows with offset-0 DateTimes store the
      # literal. Probe5/probe6 verified both directions (Mar: +5, Jul: +4).
      json_create
      booking = SubSpaceBooking.find_by!(name: "Fresh")
      expect(raw_utc_wall(booking)).to eq("2027-03-03 15:00:00")
    end

    context "blocking" do
      it "redirects a non-admin JSON-boolean blocking request with an alert but still books it" do
        # WART(D-B03) (controller:219): the permission check uses `== true`, matches
        # JSON booleans, and has NO `return` after redirect_to — the flow
        # continues into book() and the blocking row persists.
        json_create(blocking: true)
        expect(response.status).to eq(302)
        expect(flash[:alert])
          .to eq("You do not have permission to block a space.")
        booking = SubSpaceBooking.find_by!(name: "Fresh")
        expect(booking.blocking).to be(true)
        expect(status_name(booking)).to eq("Approved")
      end

      it "admin JSON boolean blocking is created" do
        admin = create(:user, :admin, booking_approval: true)
        log_in!(admin)
        post sub_space_booking_index_path, as: :json,
             params: { sub_space_booking: {
               sub_space_id: subspace.id, start_time: "2027-03-03 10:00",
               end_time: "2027-03-03 12:00", name: "Block", description: "D",
               blocking: true
             } }
        expect(response.status).to eq(204)
        booking = SubSpaceBooking.find_by!(name: "Block")
        expect(booking.blocking).to be(true)
        expect(status_name(booking)).to eq("Approved")
      end

      it "skips the overlap check when params[:blocking] is the string 'true'" do
        # WART(D-B04/D-B27) (controller:335): `params[:...] != "true"` — an HTML form string
        # bypasses the overlap query entirely, so a regular user can block.
        json_create(blocking: "true")
        expect(response.status).to eq(204)
        booking = SubSpaceBooking.find_by!(name: "Fresh")
        expect(booking.blocking).to be(true)
      end

      it "destroys the booking and reports TimeSlot when a literal-wall blocking row overlaps" do
        # Overlap detection compares the new booking's wall (parsed at offset
        # 0) against stored rows; factory rows store the literal wall, so
        # factory-vs-controller overlaps are detected.
        set_booking_status!(
          create(:sub_space_booking, sub_space: subspace, user: user,
                                     start_time: DateTime.parse("2027-03-03 09:00"),
                                     end_time: DateTime.parse("2027-03-03 12:00"),
                                     name: "Taker", blocking: true),
          @approved_status
        )
        json_create
        expect(response.status).to eq(422)
        expect(response.parsed_body).to eq(
          "errors" => ["TimeSlot This time slot is already booked."]
        )
        expect(SubSpaceBooking.where(name: "Fresh")).to be_empty
        expect(SubSpaceBooking.exists?(name: "Taker")).to be(true)
      end

      it "misses overlaps between two controller-created bookings" do
        # WART(D-B06): controller-created rows store the EDT/EST-shifted wall while
        # the overlap binds use the literal wall, so JSON booking 11:00-12:00
        # never collides with the 10:00-12:00 block stored at 15:00-17:00.
        admin = create(:user, :admin, booking_approval: true)
        log_in!(admin)
        post sub_space_booking_index_path, as: :json,
             params: { sub_space_booking: {
               sub_space_id: subspace.id, start_time: "2027-03-03 10:00",
               end_time: "2027-03-03 12:00", name: "Blk", description: "D",
               blocking: true
             } }
        expect(response.status).to eq(204)
        post sub_space_booking_index_path, as: :json,
             params: { sub_space_booking: {
               sub_space_id: subspace.id, start_time: "2027-03-03 11:00",
               end_time: "2027-03-03 12:00", name: "Sneak", description: "D"
             } }
        expect(response.status).to eq(204)
        sneak = SubSpaceBooking.find_by!(name: "Sneak")
        # stored wall was shifted +5h (March → EST)
        expect(raw_utc_wall(sneak)).to eq("2027-03-03 16:00:00")
      end
    end
  end

  # ------------------------------------------------------- recurring bookings

  describe "POST create recurring" do
    let(:user) { create(:user, :regular_user, booking_approval: true) }
    let(:subspace) { create(:sub_space) }

    before { log_in!(user) }

    it "rejects recurring without end/frequency with a string error" do
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-02-03 10:00",
             end_time: "2027-02-03 11:00", name: "R", description: "D",
             recurring: true
           } }
      expect(response.status).to eq(422)
      expect(response.parsed_body)
        .to eq("errors" => "Invalid recurring parameters")
    end

    it "creates a weekly series; recurring_end is date-INCLUSIVE (loop-while < start)" do
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-02-03 10:00",
             end_time: "2027-02-03 11:00", name: "Weekly", description: "D",
             recurring: true, recurring_frequency: "weekly",
             recurring_end: "2027-02-17"
           } }
      expect(response.status).to eq(204)
      walls = SubSpaceBooking.where(name: "Weekly").order(:start_time)
                             .map { |b| raw_utc_wall(b)[0..9] }
      expect(walls).to eq(
        ["2027-02-03", "2027-02-10", "2027-02-17"]
      )
      expect(SubSpaceBooking.where(name: "Weekly").select { |b| b.recurring_booking_id.present? }.size)
        .to eq(3)
    end

    # WART(D-B08): each occurrence advances from the previous one, so the day drifts
    it "monthly series clamps day-of-month (Jan 31 → Feb 28 ...) and drifts" do
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-01-31 10:00",
             end_time: "2027-01-31 11:00", name: "Monthly", description: "D",
             recurring: true, recurring_frequency: "monthly",
             recurring_end: "2027-06-28"
           } }
      expect(response.status).to eq(204)
      walls = SubSpaceBooking.where(name: "Monthly").order(:start_time)
                             .map { |b| raw_utc_wall(b)[0..9] }
      expect(walls).to eq(
        ["2027-01-31", "2027-02-28", "2027-03-28", "2027-04-28",
         "2027-05-28", "2027-06-28"]
      )
    end

    it "recurring_end == start date creates exactly one booking" do
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-01-31 10:00",
             end_time: "2027-01-31 11:00", name: "OneOnly", description: "D",
             recurring: true, recurring_frequency: "monthly",
             recurring_end: "2027-01-31"
           } }
      expect(response.status).to eq(204)
      expect(SubSpaceBooking.where(name: "OneOnly").count).to eq(1)
    end

    it "broken mid-series conflicts leave 422 + partial series" do
      set_booking_status!(
        create(:sub_space_booking, sub_space: subspace, user: user,
               start_time: DateTime.parse("2027-02-17 10:30"),
               end_time: DateTime.parse("2027-02-17 11:30"),
               name: "Grabber", blocking: true),
        @approved_status
      )
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-02-03 10:00",
             end_time: "2027-02-03 11:00", name: "Weekly", description: "D",
             recurring: true, recurring_frequency: "weekly",
             recurring_end: "2027-02-17"
           } }
      expect(response.status).to eq(422)
      expect(response.parsed_body)
        .to eq("errors" => ["TimeSlot This time slot is already booked."])
      walls = SubSpaceBooking.where(name: "Weekly").order(:start_time)
                             .map { |b| raw_utc_wall(b)[0..9] }
      expect(walls).to eq(["2027-02-03", "2027-02-10"])
    end

    it "two mid-series conflicts explode with 500 (DoubleRenderError) leaving the first booking" do
      # WART(D-B07): book()'s conflict branch calls booking.destroy + render for each
      # conflicting occurrence; the second render raises
      # ActionView::DoubleRenderError → Rails 500 error page.
      set_booking_status!(
        create(:sub_space_booking, sub_space: subspace, user: user,
               start_time: DateTime.parse("2027-02-10 10:30"),
               end_time: DateTime.parse("2027-02-10 11:30"),
               name: "Grabber1", blocking: true),
        @approved_status
      )
      set_booking_status!(
        create(:sub_space_booking, sub_space: subspace, user: user,
               start_time: DateTime.parse("2027-02-17 10:30"),
               end_time: DateTime.parse("2027-02-17 11:30"),
               name: "Grabber2", blocking: true),
        @approved_status
      )
      post sub_space_booking_index_path, as: :json,
           params: { sub_space_booking: {
             sub_space_id: subspace.id, start_time: "2027-02-03 10:00",
             end_time: "2027-02-03 11:00", name: "Weekly", description: "D",
             recurring: true, recurring_frequency: "weekly",
             recurring_end: "2027-02-17"
           } }
      expect(response.status).to eq(500)
      expect(SubSpaceBooking.where(name: "Weekly").count).to eq(1)
    end
  end

  # ----------------------------------------------------------- bookings feed

  describe "GET bookings (calendar JSON contract)" do
    let(:space) { create(:space) }
    let(:subspace) { create(:sub_space, space: space) }
    let(:viewer) { create(:user, :regular_user, booking_approval: true) }
    let(:admin_viewer) { create(:user, :admin, booking_approval: true) }
    let(:owner) { create(:user, :regular_user, booking_approval: true) }

    # April 2027 → EDT (-04:00). Factory rows store the literal wall.
    def feed_booking(attrs = {})
      set_booking_status!(
        create(:sub_space_booking,
               { sub_space: subspace, user: owner,
                 start_time: DateTime.parse("2027-04-03 10:00"),
                 end_time: DateTime.parse("2027-04-03 11:00") }.merge(attrs)),
        @approved_status
      )
    end

    def feed(room: subspace.id, user: viewer)
      log_in!(user)
      get bookings_sub_space_booking_index_path, params: { room: room }
      expect(response).to have_http_status(:ok)
      response.parsed_body
    end

    it "renders the exact event shape with EDT millisecond+zone timestamps" do
      # WART(D-B06) round-trip: factory rows with offset-0 DateTimes store the
      # literal wall (10:00/11:00); the readback evaluates that wall as UTC
      # and re-formats it in the app's Eastern zone, so the feed shows
      # 06:00/07:00-04:00, NOT the values a user entered into the form.
      feed_booking(name: "Laser Safety", description: "Laser 101",
                   public: true)

      events = feed
      expect(events).to contain_exactly(
        "id" => "booking_#{SubSpaceBooking.find_by(name: 'Laser Safety').id}_#{subspace.id}",
        "title" => "Laser Safety - Laser 101",
        "start" => "2027-04-03T06:00:00.000-04:00",
        "end" => "2027-04-03T07:00:00.000-04:00",
        "color" => "#497979" # somebody else's confirmed booking
      )
    end

    it "colors the viewer's own confirmed booking with your_confirmed" do
      feed_booking(
        name: "Mine", description: "D", public: false,
        user: viewer, start_time: DateTime.parse("2027-04-05 08:00"),
        end_time: DateTime.parse("2027-04-05 09:00")
      )
      events = feed(user: viewer)
      expect(events.first["title"]).to eq("Mine - D")
      expect(events.first["color"]).to eq("#49794b")
      expect(events.first["start"]).to eq("2027-04-05T04:00:00.000-04:00")
    end

    it "shows the owner their pending booking with (Pending) suffix + color" do
      booking = feed_booking(name: "Mine", description: "D", public: false,
                             user: viewer)
      set_booking_status!(booking, @pending_status)

      events = feed(user: viewer)
      expect(events.size).to eq(1)
      expect(events.first["title"]).to eq("Mine - D (Pending)")
      expect(events.first["color"]).to eq("#B5A500")
    end

    it "hides other users' private bookings behind the Space Booked title" do
      feed_booking(name: "Private", description: "hidden", public: false)
      other = feed
      expect(other.first["title"]).to eq("Space Booked")
      expect(other.first["color"]).to eq("#497979")
    end

    it "shows public bookings to everyone" do
      feed_booking(name: "Public", description: "open", public: true)
      events = feed
      expect(events.first["title"]).to eq("Public - open")
    end

    it "excludes declined bookings" do
      declined = feed_booking(name: "Gone", description: "D", public: true)
      set_booking_status!(declined, @declined_status)
      expect(feed).to be_empty
    end

    it "appends the owner name for admins viewing other users' pending bookings" do
      booking = feed_booking(name: "Oth", description: "D", public: false)
      set_booking_status!(booking, @pending_status)
      events = feed(user: admin_viewer)
      expect(events.first["title"])
        .to eq("Oth - D (Pending) - #{owner.name}")
      expect(events.first["color"]).to eq("#FFA500")
    end

    it "plays Space Blocked for non-owner viewers of blocking bookings (admins too)" do
      feed_booking(name: "Hold", description: "D", public: false,
                   blocking: true)
      events = feed
      expect(events.first["title"]).to eq("Space Blocked")
      # blocking titles keep the blocking color even for the viewer
      expect(events.first["color"]).to eq("#ABABABFF")
      # WART(D-B10) (controller:195): (!admin || owner!=viewer) is TRUE for admins
      # viewing someone else's block, so they also only see "Space Blocked".
      expect(feed(user: admin_viewer).first["title"]).to eq("Space Blocked")
    end

    it "answers an empty list without a room param" do
      expect(feed(room: nil)).to be_empty
    end
  end

  # ---------------------------------------------------------- edit + update

  describe "edit/update" do
    let(:space) { create(:space) }
    let(:subspace) { create(:sub_space, space: space) }
    let(:owner) { create(:user, :regular_user, booking_approval: true) }
    let(:other) { create(:user, :regular_user, booking_approval: true) }

    def owned_booking(status: nil, **attrs)
      set_booking_status!(
        create(:sub_space_booking, { sub_space: subspace, user: owner,
               start_time: DateTime.parse("2027-03-03 10:00"),
               end_time: DateTime.parse("2027-03-03 11:00") }.merge(attrs)),
        (status || @pending_status)
      )
    end

    # Routes use a custom :sub_space_booking_id member key (delete even has it
    # twice), so helpers need the explicit hash.
    def edit_path(booking_or_id)
      id = booking_or_id.is_a?(Integer) ? booking_or_id : booking_or_id.id
      sub_space_booking_edit_path(sub_space_booking_id: id)
    end

    def update_path(booking_or_id)
      id = booking_or_id.is_a?(Integer) ? booking_or_id : booking_or_id.id
      sub_space_booking_update_path(sub_space_booking_id: id)
    end

    it "renders the edit form for the owner of a PENDING booking" do
      log_in!(owner)
      booking = owned_booking
      get edit_path(booking)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Booking")
      expect(response.body).to include("bookingEdit")
    end

    # WART(D-B11): owners are bounced from editing their own APPROVED bookings
    it "redirects owners away from editing their own APPROVED booking" do
      log_in!(owner)
      booking = owned_booking(status: @approved_status)
      get edit_path(booking)
      expect(response).to redirect_to(sub_space_booking_index_path)
      expect(flash[:alert])
        .to eq("You can't access this subspace booking.")
    end

    it "keeps a non-owner regular user out with the owner-or-admin alert" do
      log_in!(other)
      booking = owned_booking
      get edit_path(booking)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert])
        .to eq("You must be the owner of this booking or an admin to delete it.")
    end

    it "admins edit any booking (owner check passes for admins)" do
      admin = create(:user, :admin, booking_approval: true)
      log_in!(admin)
      booking = owned_booking
      get edit_path(booking)
      expect(response).to have_http_status(:ok)
    end

    it "non-owners can't reach update either" do
      log_in!(other)
      booking = owned_booking
      patch update_path(booking), params: {
        sub_space_booking: {
          start_time: "2027-03-03 12:00", end_time: "2027-03-03 13:00",
          name: "Hacked", description: "D"
        }
      }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert])
        .to eq("You must be the owner of this booking or an admin to delete it.")
      expect(booking.reload.name).not_to eq("Hacked")
    end

    it "moves a PENDING booking via PATCH + flash, storing the literal wall" do
      log_in!(owner)
      booking = owned_booking
      patch update_path(booking), params: {
        sub_space_booking: {
          start_time: "2027-03-03 12:00", end_time: "2027-03-03 13:00",
          name: "Moved", description: "D"
        }
      }
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-calendar-tab", room: subspace.id)
      )
      expect(flash[:notice]).to eq("Successfully updated booking")
      expect(raw_utc_wall(booking.reload)).to eq("2027-03-03 17:00:00")
    end

    it "JSON PATCH update returns {status: ok}" do
      log_in!(owner)
      booking = owned_booking
      patch update_path(booking), as: :json, params: {
        sub_space_booking: {
          start_time: "2027-03-03 12:00", end_time: "2027-03-03 13:00",
          name: "Json", description: "D"
        }
      }
      expect(response.status).to eq(200)
      expect(response.parsed_body).to eq("status" => "ok")
      expect(booking.reload.name).to eq("Json")
      expect(booking.reload.sub_space_booking_status.booking_status.name)
        .to eq("Pending") # stays pending when updated
    end

    # WART(D-B11): the same bounce applies to PATCH update
    it "bounces an owner updating their own APPROVED booking with a permission alert" do
      log_in!(owner)
      booking = owned_booking(status: @approved_status)
      patch update_path(booking), params: {
        sub_space_booking: {
          start_time: "2027-03-03 12:00", end_time: "2027-03-03 13:00",
          name: "ApprovedEdit", description: "D"
        }
      }
      expect(response).to redirect_to(sub_space_booking_index_path(
        anchor: "booking-calendar-tab", room: subspace.id
      ))
      expect(flash[:alert])
        .to eq("You do not have permission to edit this booking")
      expect(booking.reload.name).not_to eq("ApprovedEdit")
    end

    it "invalid update re-renders the edit form HTML" do
      log_in!(owner)
      booking = owned_booking
      patch update_path(booking), params: {
        sub_space_booking: {
          start_time: "2027-03-03 12:00", end_time: "2027-03-03 10:00",
          name: "Bad", description: "D"
        }
      }
      expect(response.status).to eq(200)
      expect(response.body).to include("Edit Booking")
      # nothing got persisted; the wall is still the factory's literal 10:00
      expect(raw_utc_wall(booking.reload)).to eq("2027-03-03 10:00:00")
    end

    it "update accepts PATCH but 404s on PUT (route constraint)" do
      log_in!(owner)
      booking = owned_booking
      put update_path(booking), params: {
        sub_space_booking: { name: "Nope" }
      }
      expect(response.status).to eq(404)
      expect(booking.reload.name).not_to eq("Nope")
    end

    it "unknown booking id → ActiveRecord::RecordNotFound (404)" do
      log_in!(owner)
      get edit_path(99_999_999)
      expect(response.status).to eq(404)
      patch update_path(99_999_999),
            params: { sub_space_booking: { name: "x" } }
      expect(response.status).to eq(404)
    end
  end

  # ------------------------------------------------ approve / decline / publish

  describe "approve, decline, publish, bulk" do
    let(:space) { create(:space) }
    let(:subspace) { create(:sub_space, space: space) }

    def booking_by(user, **attrs)
      set_booking_status!(
        create(:sub_space_booking,
               { sub_space: subspace, user: user,
                 start_time: DateTime.parse("2027-04-03 10:00"),
                 end_time: DateTime.parse("2027-04-03 11:00") }.merge(attrs)),
        @pending_status
      )
    end

    it "user gate on approve/decline" do
      log_in!(create(:user, :regular_user, booking_approval: true))
      booking = booking_by(create(:user, :regular_user, booking_approval: true))
      put sub_space_booking_approve_path(
        sub_space_booking_id: booking.id
      )
      expect(response).to redirect_to(root_path)
      expect(flash[:alert])
        .to eq("You must be an admin or staff to view this page.")
      expect(status_name(booking)).to eq("Pending")
    end

    it "staff approve sets status + approved_by + approved_at" do
      staff = create(:user, :staff, booking_approval: true)
      log_in!(staff)
      booking = booking_by(create(:user, :regular_user, booking_approval: true))
      # freeze the clock AFTER login (the session expires 72h from sign-in, so
      # travelling to a distant fixed date would sign the staff user out)
      frozen_now = Time.zone.now.change(usec: 0)
      travel_to(frozen_now)

      put sub_space_booking_approve_path(
        sub_space_booking_id: booking.id
      )
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-admin-tab")
      )
      expect(flash[:notice])
        .to eq("Booking for #{subspace.name} approved successfully.")
      expect(status_name(booking)).to eq("Approved")
      expect(booking.reload.approved_by_id).to eq(staff.id)
      expect(booking.approved_at).to eq(frozen_now)
    end

    it "approve unknown id → 404" do
      log_in!(create(:user, :admin, booking_approval: true))
      put sub_space_booking_approve_path(
        sub_space_booking_id: 99_999_999
      )
      expect(response.status).to eq(404)
    end

    it "decline flips the status" do
      staff = create(:user, :staff, booking_approval: true)
      log_in!(staff)
      booking = booking_by(create(:user, :regular_user, booking_approval: true))
      put sub_space_booking_decline_path(sub_space_booking_id: booking.id)
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-admin-tab")
      )
      expect(flash[:notice])
        .to eq("Booking for #{subspace.name} declined successfully.")
      expect(status_name(booking)).to eq("Declined")
    end

    it "publish needs admin; admin toggles public/private" do
      log_in!(create(:user, :regular_user, booking_approval: true))
      booking = booking_by(create(:user, :regular_user, booking_approval: true),
                           public: false)
      put sub_space_booking_publish_path(sub_space_booking_id: booking.id)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You must be an admin to view this page.")
      expect(booking.reload.public).to be(false)

      log_in!(create(:user, :admin, booking_approval: true))
      put sub_space_booking_publish_path(sub_space_booking_id: booking.id)
      expect(flash[:notice]).to eq("Booking made public successfully.")
      expect(booking.reload.public).to be(true)
      put sub_space_booking_publish_path(sub_space_booking_id: booking.id)
      expect(flash[:notice]).to eq("Booking made private successfully.")
      expect(booking.reload.public).to be(false)
    end

    # WART(D-B01) (controller:before_action list): bulk_approve_decline is NOT gated
    # by user_admin_or_staff — any signed-in user can bulk-approve/decline.
    it "any signed-in user can bulk_approve_decline" do
      nobody = create(:user, :regular_user, booking_approval: true)
      log_in!(nobody)
      b1 = booking_by(create(:user, :regular_user, booking_approval: true))
      b2 = booking_by(create(:user, :regular_user, booking_approval: true))

      put bulk_approve_decline_sub_space_booking_index_path,
          params: { sub_space_booking_ids: [b1.id, b2.id],
                    bulk_status: "approve" }
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-admin-tab")
      )
      expect(flash[:notice]).to eq("Bookings approved successfully.")
      expect(status_name(b1)).to eq("Approved")
      expect(status_name(b2)).to eq("Approved")

      put bulk_approve_decline_sub_space_booking_index_path,
          params: { sub_space_booking_ids: [b1.id], bulk_status: "decline" }
      expect(flash[:notice]).to eq("Bookings declined successfully.")
      expect(status_name(b1)).to eq("Declined")
    end

    it "bulk_approve_decline edge flashes" do
      log_in!(create(:user, :regular_user, booking_approval: true))
      put bulk_approve_decline_sub_space_booking_index_path
      expect(flash[:alert]).to eq("No bookings selected.")

      b = booking_by(create(:user, :regular_user, booking_approval: true))
      put bulk_approve_decline_sub_space_booking_index_path,
          params: { sub_space_booking_ids: [b.id], bulk_status: "wibble" }
      expect(flash[:alert]).to eq("Failed to bulk update booking status.")
      expect(status_name(b)).to eq("Pending")
    end
  end

  # ----------------------------------------------------------------- delete

  describe "delete + delete_remaining_recurring" do
    let(:space) { create(:space) }
    let(:subspace) { create(:sub_space, space: space) }

    def booking_for(user, **attrs)
      set_booking_status!(
        create(:sub_space_booking,
               { sub_space: subspace, user: user,
                 start_time: DateTime.parse("2027-04-03 10:00"),
                 end_time: DateTime.parse("2027-04-03 11:00") }.merge(attrs)),
        @approved_status
      )
    end

    it "owner delete works (status row unlinked first — architecture.md §5.3.1)" do
      owner = create(:user, :regular_user, booking_approval: true)
      log_in!(owner)
      booking = booking_for(owner)
      status_id = booking.sub_space_booking_status_id

      delete sub_space_booking_delete_path(booking.id)
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-tab")
      )
      expect(flash[:notice])
        .to(eq("Booking for #{subspace.name} deleted successfully."))
      expect(SubSpaceBooking.find_by(id: booking.id)).to be_nil
      expect(SubSpaceBookingStatus.find_by(id: status_id)).to be_nil
    end

    it "non-owner hit gets the owner-or-admin alert and the row survives" do
      log_in!(create(:user, :regular_user, booking_approval: true))
      booking = booking_for(create(:user, :regular_user, booking_approval: true))
      delete sub_space_booking_delete_path(booking.id)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert])
        .to eq("You must be the owner of this booking or an admin to delete it.")
      expect(SubSpaceBooking.exists?(booking.id)).to be(true)
    end

    it "admins delete anyone's bookings" do
      log_in!(create(:user, :admin, booking_approval: true))
      booking = booking_for(create(:user, :regular_user, booking_approval: true))
      delete sub_space_booking_delete_path(booking.id)
      expect(flash[:notice])
        .to eq("Booking for #{subspace.name} deleted successfully.")
      expect(SubSpaceBooking.find_by(id: booking.id)).to be_nil
    end

    it "unknown id → 404 (raised by the before_action finder)" do
      log_in!(create(:user, :admin, booking_approval: true))
      delete sub_space_booking_delete_path(99_999_999)
      expect(response.status).to eq(404)
    end

    it "delete_remaining_recurring clears from THIS booking onward" do
      owner = create(:user, :regular_user, booking_approval: true)
      log_in!(owner)
      recurring = RecurringBooking.create!
      b1 = booking_for(owner, recurring_booking: recurring)
      b2 = booking_for(owner, recurring_booking: recurring,
             start_time: DateTime.parse("2027-04-10 10:00"),
             end_time: DateTime.parse("2027-04-10 11:00"))
      delete delete_remaining_recurring_sub_space_booking_path(b1.id)
      expect(flash[:notice])
        .to eq("Remaining bookings for #{subspace.name} deleted successfully.")
      expect(SubSpaceBooking.where(id: [b1.id, b2.id])).to be_empty
    end

    it "non-recurring bookings hit the not-attached notice" do
      owner = create(:user, :regular_user, booking_approval: true)
      log_in!(owner)
      booking = booking_for(owner)
      delete delete_remaining_recurring_sub_space_booking_path(booking.id)
      expect(flash[:notice])
        .to eq("Booking is not attached to a recurring booking.")
      expect(SubSpaceBooking.exists?(booking.id)).to be(true)
    end
  end

  # ------------------------------------------------ users + get_sub_space_booking + access

  describe "users / get_sub_space_booking / access requests" do
    let(:space) { create(:space) }

    it "users leaks access_token-esque attributes (admin/staff only)" do
      # WART(D-B02): `render json: User.all` — the raw record serializer; regular
      # users can't reach it, but staff/admin expose every column incl.
      # access_token.
      log_in!(create(:user, :regular_user, booking_approval: true))
      get users_sub_space_booking_index_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert])
        .to eq("You must be an admin or staff to view this page.")

      log_in!(create(:user, :admin, booking_approval: true))
      create(:user, :regular_user, booking_approval: true)
      get users_sub_space_booking_index_path
      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json).to be_an(Array)
      keys = json.map(&:keys).flatten
      expect(keys).to include("access_token", "email", "name", "password")
    end

    it "get_sub_space_booking admins/staff only: 404 on unknown id" do
      log_in!(create(:user, :admin, booking_approval: true))
      get get_sub_space_booking_sub_space_booking_index_path, params: { id: 99_999_999 }
      expect(response.status).to eq(404)

      booking = set_booking_status!(
        create(:sub_space_booking, sub_space: create(:sub_space, space: space),
               user: create(:user, :regular_user, booking_approval: true)),
        @pending_status
      )
      get get_sub_space_booking_sub_space_booking_index_path,
          params: { id: booking.id }
      expect(response.status).to eq(200)
      expect(response.parsed_body).to include(
        "id" => booking.id,
        "name" => booking.name,
        "sub_space_id" => booking.sub_space_id
      )
    end

    it "request_access gates blank comments and duplicate requests" do
      user = create(:user, :regular_user, booking_approval: false)
      log_in!(user)

      put request_access_sub_space_booking_index_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert])
        .to eq("Please provide a reason for booking access.")

      put request_access_sub_space_booking_index_path,
          params: { comments: "please", identity: "Other" }
      expect(flash[:notice]).to eq("Access request submitted successfully.")
      uba = UserBookingApproval.find_by!(user: user)
      expect(uba.identity).to eq("Other")
      expect(uba.approved).to be(false)

      # duplicate attempt does not create a second row
      put request_access_sub_space_booking_index_path,
          params: { comments: "again", identity: "GNG" }
      expect(flash[:alert]).to eq("You have already requested access.")
      expect(UserBookingApproval.where(user: user).count).to eq(1)
    end

    it "request_access identity 'JMTS' without a JMTS Space 500s" do
      # WART(D-B16): `Space.find_by(name: "JMTS").space_managers` — nil receiver.
      user = create(:user, :regular_user, booking_approval: false)
      log_in!(user)
      put request_access_sub_space_booking_index_path,
          params: { comments: "j", identity: "JMTS" }
      expect(response.status).to eq(500)
      expect(UserBookingApproval.find_by(user: user)).not_to be_nil
    end

    it "request_access identity 'JMTS' with a JMTS Space submits fine" do
      create(:space, :with_space_managers, name: "JMTS")
      user = create(:user, :regular_user, booking_approval: false)
      log_in!(user)
      put request_access_sub_space_booking_index_path,
          params: { comments: "j", identity: "JMTS" }
      expect(flash[:notice]).to eq("Access request submitted successfully.")
      expect(UserBookingApproval.find_by(user: user).identity).to eq("JMTS")
    end

    it "request_access identity 'Staff' needs a resolvable supervisor" do
      user = create(:user, :regular_user, booking_approval: false)
      log_in!(user)
      put request_access_sub_space_booking_index_path,
          params: { comments: "hey", identity: "Staff" }
      expect(response.status).to eq(404)
      # WART(D-B15): the UBA row is saved BEFORE the supervisor lookup 404s, so the
      # request exists (staff_id nil) but no notification email went out.
      uba = UserBookingApproval.find_by(user: user)
      expect(uba.identity).to eq("Staff")
      expect(uba.staff_id).to be_nil
      expect(uba.approved).to be(false)
    end

    it "request_access identity 'Staff' with a supervisor id submits" do
      user = create(:user, :regular_user, booking_approval: false)
      log_in!(user)
      supervisor = create(:user, :admin)
      put request_access_sub_space_booking_index_path,
          params: { comments: "hey", identity: "Staff",
                    supervisor: supervisor.id }
      expect(flash[:notice]).to eq("Access request submitted successfully.")
      expect(UserBookingApproval.where(user: user).count).to eq(1)
    end

    it "approve_access with user_id grants a fresh 'Other' UBA" do
      admin = create(:user, :admin, booking_approval: true)
      log_in!(admin)
      fresh = create(:user, :regular_user, booking_approval: false)

      put approve_access_sub_space_booking_index_path, params: { user_id: fresh.id }
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-admin-tab")
      )
      expect(flash[:notice]).to eq("Access granted successfully.")
      uba = UserBookingApproval.find_by!(user: fresh)
      expect(uba.approved).to be(true)
      expect(uba.identity).to eq("Other")
      expect(uba.staff_id).to eq(admin.id)
      expect(fresh.reload.booking_approval).to be(true)
    end

    it "deny_access destroys the UBA and revokes user approval" do
      admin = create(:user, :admin, booking_approval: true)
      log_in!(admin)
      user1 = create(:user, :regular_user, booking_approval: true)
      uba = UserBookingApproval.create!(user: user1, identity: "JMTS",
                                        approved: true, comments: "why",
                                        date: Date.today)

      put deny_access_sub_space_booking_index_path, params: { id: uba.id }
      expect(response).to redirect_to(
        sub_space_booking_index_path(anchor: "booking-admin-tab")
      )
      expect(flash[:notice]).to eq("Access request declined successfully.")
      expect(UserBookingApproval.find_by(id: uba.id)).to be_nil
      expect(user1.reload.booking_approval).to be(false)
    end

    it "bulk_approve_access grants many approvals" do
      admin = create(:user, :admin, booking_approval: true)
      log_in!(admin)
      ubas = 2.times.map do
        u = create(:user, :regular_user, booking_approval: false)
        UserBookingApproval.create!(user: u, identity: "GNG", approved: false,
                                    comments: "gng", date: Date.today)
      end
      put bulk_approve_access_sub_space_booking_index_path,
          params: { user_booking_approval_ids: ubas.map(&:id) }
      expect(flash[:notice])
        .to eq("All selected access requests approved successfully.")
      expect(ubas.map { |uba| uba.reload.approved }).to all(be(true))
      expect(ubas.map { |uba| uba.user.reload.booking_approval }).to all(be(true))
    end

    it "bulk_approve_access with nothing selected alerts" do
      log_in!(create(:user, :admin, booking_approval: true))
      put bulk_approve_access_sub_space_booking_index_path
      expect(flash[:alert]).to eq("No approvals selected.")
    end
  end
end
