# frozen_string_literal: true

require "rails_helper"

# The booking page outside the calendar (entrypoints/sub_space_booking.js):
# the access-request form, the tabs, the admin panel's selection boxes, the
# recurring-approval modal and the user search.

RSpec.describe "Sub-space booking: access and admin panel", :booking_clock, type: :system do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
  end

  let(:space) { create(:space, name: "Maker Hall") }
  let(:subspace) { create(:sub_space, space: space, name: "Laser Room") }
  let(:admin) { create(:user, :admin, name: "Ada Admin", booking_approval: true) }
  let(:eastern) { ActiveSupport::TimeZone["Eastern Time (US & Canada)"] }

  def open_admin_panel(path = sub_space_booking_index_path(room: subspace.id, anchor: "booking-admin-tab"))
    log_in_as(admin)
    visit path
    expect(page).to have_css("#booking-admin-tab.active.show", visible: :all)
  end

  def pending_booking(name, start: eastern.local(2027, 3, 16, 10), **attrs)
    create(:sub_space_booking, sub_space: subspace, name: name, start_time: start, end_time: start + 1.hour, **attrs)
  end

  describe "the access request form" do
    let(:newcomer) { create(:user, :regular_user, name: "Nina Newcomer", booking_approval: false) }

    it "shows the supervisor list only for the Staff identity", js: true, skip_bullet: true do
      log_in_as(newcomer)
      visit sub_space_booking_index_path(room: subspace.id)

      expect(page).to have_css("#supervisor-select", visible: :hidden)
      choose "identity_staff"
      expect(page).to have_css("#supervisor-select", visible: :visible)
      choose "identity_gng"
      expect(page).to have_css("#supervisor-select", visible: :hidden)
      choose "identity_staff"
      choose "identity_other"
      expect(page).to have_css("#supervisor-select", visible: :hidden)
    end

    it "records a request with the identity and reason given", js: true, skip_bullet: true do
      log_in_as(newcomer)
      visit sub_space_booking_index_path(room: subspace.id)
      choose "identity_other"
      fill_in "comments", with: "Capstone laser cutting"
      click_button "Submit Request"

      expect(page).to have_text("Access request submitted successfully.")
      request = UserBookingApproval.find_by!(user: newcomer)
      expect(request.identity).to eq("Other")
      expect(request.comments).to eq("Capstone laser cutting")
      expect(request.approved).to be(false)
    end
  end

  describe "the tabs" do
    it "switches between Book Room, My Bookings and Admin Panel without leaving the page", js: true, skip_bullet: true do
      log_in_as(admin)
      visit sub_space_booking_index_path(room: subspace.id)

      expect(page).to have_css("#booking-calendar-tab.active.show", visible: :all)
      find("#booking-tab-btn").click
      expect(page).to have_css("#booking-tab.active.show", visible: :all)
      expect(page).to have_css("#booking-calendar-tab:not(.active)", visible: :all)
      expect(page).to have_css("#booking-tab-btn.active")
      expect(page).to have_css("#booking-calendar-tab-btn:not(.active)")
      find("#booking-admin-tab-btn").click
      expect(page).to have_css("#booking-admin-tab.active.show", visible: :all)
      expect(page).to have_current_path(/room=#{subspace.id}/)
    end

    it "opens the tab named by the address anchor", js: true, skip_bullet: true do
      log_in_as(admin)
      visit "#{sub_space_booking_index_path(room: subspace.id)}#booking-tab"

      expect(page).to have_css("#booking-tab.active.show", visible: :all)
    end

    it "opens the admin tab when a page parameter of one of its tables is given", js: true, skip_bullet: true do
      log_in_as(admin)
      visit "#{sub_space_booking_index_path(room: subspace.id)}&approved_page=1"

      expect(page).to have_css("#booking-admin-tab.active.show", visible: :all)
    end
  end

  describe "pending bookings" do
    let!(:first) { pending_booking("Soldering club") }
    let!(:second) { pending_booking("Robotics", start: eastern.local(2027, 3, 17, 10)) }

    it "ticks and clears every pending booking with the header box", js: true, skip_bullet: true do
      open_admin_panel
      find("#pending_bookings_select_all").check
      expect(page).to have_checked_field("booking_#{first.id}")
      expect(page).to have_checked_field("booking_#{second.id}")

      find("#pending_bookings_select_all").uncheck
      expect(page).to have_unchecked_field("booking_#{first.id}")
      expect(page).to have_unchecked_field("booking_#{second.id}")
    end

    it "approves the ticked bookings together", js: true, skip_bullet: true do
      open_admin_panel
      check "booking_#{first.id}"
      find("button[form=bulkApproveDeclineForm][value=approve]").click

      expect(page).to have_text("Bookings approved successfully.")
      expect(first.reload.sub_space_booking_status.booking_status).to eq(@approved_status)
      expect(second.reload.sub_space_booking_status.booking_status).to eq(@pending_status)
    end

    it "declines every booking when all are ticked and Bulk Reject is pressed", js: true, skip_bullet: true do
      open_admin_panel
      find("#pending_bookings_select_all").check
      click_button "Bulk Reject Selected"

      expect(page).to have_text("Bookings declined successfully.")
      expect([first, second].map { |b| b.reload.sub_space_booking_status.booking_status }).to all(eq(@declined_status))
    end

    it "approves a single booking with its own button", js: true, skip_bullet: true do
      open_admin_panel
      within(find("tr", text: "Soldering club")) { click_button "Approve" }

      expect(page).to have_text("approved successfully")
      expect(first.reload.sub_space_booking_status.booking_status).to eq(@approved_status)
    end
  end

  describe "a recurring request" do
    let!(:recurring) { RecurringBooking.create! }

    before do
      [eastern.local(2027, 3, 16, 10), eastern.local(2027, 3, 23, 10)].each do |start|
        pending_booking("Club night", start: start, recurring_booking_id: recurring.id)
      end
    end

    it "lists the series once, with the number of dates", js: true, skip_bullet: true do
      open_admin_panel

      expect(page).to have_css("table.table-sub-space-booking-pending tbody tr", count: 1)
      expect(page).to have_text("Recurring (2)")
    end

    it "approves every date with the double-check button", js: true, skip_bullet: true do
      open_admin_panel
      find("button[title='Approve All']").click

      expect(page).to have_text("Bookings approved successfully.")
      expect(SubSpaceBooking.where(name: "Club night").map { |b| b.sub_space_booking_status.booking_status }).to all(eq(@approved_status))
    end

    # The modal has no container for the dates the script builds (an element
    # that is not in the page), so the script throws and the dialog shows only
    # its template row.
    it "opens the select-dates dialog with a single unlabelled template row and logs an error", js: true, skip_bullet: true do
      open_admin_panel
      find("button[title='Select Specific']").click

      expect(page).to have_css("#approveRecurringModal.show", visible: :all)
      expect(page).to have_css("#approveRecurringModal input[name='sub_space_booking_ids[]']", count: 1, visible: :all)
      expect(find("#approveRecurringModal input[name='sub_space_booking_ids[]']", visible: :all).value).to eq("")
      expect(page).to have_no_css("#recurring-checkboxes", visible: :all)
    end
  end

  describe "user permissions" do
    let!(:requester_one) { create(:user, :regular_user, name: "Rita Requester", booking_approval: false) }
    let!(:requester_two) { create(:user, :regular_user, name: "Rex Requester", booking_approval: false) }

    before do
      [requester_one, requester_two].each do |u|
        UserBookingApproval.create!(user: u, identity: "Other", approved: false, comments: "need access", date: Date.today)
      end
    end

    # The bulk form wraps the per-row approve and deny forms (nested forms),
    # so the browser submits a mixed set of tokens and the app answers with its
    # stale-form message; nothing is approved.
    it "ticks every request with the header box, but submitting them together is refused as a stale form", js: true, skip_bullet: true do
      open_admin_panel
      find("#userRequestSelectAll").check
      expect(page).to have_checked_field(class: "user-request-select", count: 2)

      find("input[type=submit][value='Bulk Approve Selected']").click
      expect(page).to have_text("Your session changed; please try again.")
      expect(requester_one.reload.booking_approval).to be(false)
      expect(requester_two.reload.booking_approval).to be(false)
    end

    it "clears every request box again", js: true, skip_bullet: true do
      open_admin_panel
      find("#userRequestSelectAll").check
      find("#userRequestSelectAll").uncheck

      expect(page).to have_unchecked_field(class: "user-request-select", count: 2)
    end

    it "finds users by name in the search box and grants the chosen one access", js: true, skip_bullet: true do
      open_admin_panel
      tom_select "Rita Requester", from: "user_booking_select", search: "Rita"
      click_button "Permit Access"

      expect(page).to have_text("Access granted successfully.")
      expect(requester_one.reload.booking_approval).to be(true)
    end

    it "asks for the minimum number of characters instead of searching for a shorter text", js: true, skip_bullet: true do
      open_admin_panel
      find("#user_booking_select + .ts-wrapper .ts-control input").send_keys("Ri")

      expect(page).to have_css(".ts-dropdown .no-results", text: "Type at least 3 characters to search for a person.")
      expect(page).to have_no_css(".ts-dropdown .option")
    end

    it "stops listing people once the text is cut back below the minimum", js: true, skip_bullet: true do
      open_admin_panel
      input = find("#user_booking_select + .ts-wrapper .ts-control input")
      input.send_keys("Rit")
      expect(page).to have_css(".ts-dropdown .option", text: "Rita Requester")

      input.send_keys(:backspace)
      expect(page).to have_no_css(".ts-dropdown .option")
      expect(page).to have_css(".ts-dropdown .no-results", text: "Type at least 3 characters")

      input.send_keys(:backspace, :backspace)
      expect(page).to have_no_css(".ts-dropdown .option")
    end

    # Replaces the lookup request in the page: every call is recorded and held until the spec answers it.
    def hold_user_lookups
      page.execute_script(<<~JS)
        window.heldLookups = [];
        window.fetch = (url) => new Promise((resolve) => window.heldLookups.push({ url, resolve }));
      JS
    end

    def held_lookups
      page.evaluate_script("window.heldLookups.length")
    end

    def answer_lookup(index, status, people)
      page.execute_script(<<~JS, index, status, people)
        const [i, status, people] = arguments;
        window.heldLookups[i].resolve(new Response(JSON.stringify(people), { status }));
      JS
    end

    it "lists nothing from a failed lookup and looks the same text up again when it is typed again", js: true, skip_bullet: true do
      open_admin_panel
      hold_user_lookups
      input = find("#user_booking_select + .ts-wrapper .ts-control input")
      input.send_keys("Rit")
      wait_until("lookup not sent") { held_lookups == 1 }
      answer_lookup(0, 500, [{ id: requester_one.id, name: "Rita Requester" }])
      expect(page).to have_no_css(".ts-dropdown .option")

      input.send_keys(:backspace)
      input.send_keys("t")
      wait_until("lookup not sent again") { held_lookups == 2 }
      answer_lookup(1, 200, [{ id: requester_one.id, name: "Rita Requester" }])
      expect(page).to have_css(".ts-dropdown .option", text: "Rita Requester")
    end

    it "drops a late answer to earlier text and lists only the answer for the text in the box", js: true, skip_bullet: true do
      open_admin_panel
      hold_user_lookups
      input = find("#user_booking_select + .ts-wrapper .ts-control input")
      input.send_keys("Rit")
      wait_until("first lookup not sent") { held_lookups == 1 }
      input.send_keys("a")
      wait_until("second lookup not sent") { held_lookups == 2 }

      answer_lookup(0, 200, [{ id: requester_two.id, name: "Rex Requester" }])
      expect(page).to have_no_css(".ts-dropdown .option", text: "Rex Requester")
      answer_lookup(1, 200, [{ id: requester_one.id, name: "Rita Requester" }])
      expect(page).to have_css(".ts-dropdown .option", text: "Rita Requester")
      expect(page).to have_no_css(".ts-dropdown .option", text: "Rex Requester")
    end

    it "lists a person whose username, not name, matches the text", js: true, skip_bullet: true do
      requester_one.update!(username: "quokka42")
      open_admin_panel
      tom_select "Rita Requester", from: "user_booking_select", search: "quokka"
      click_button "Permit Access"

      expect(page).to have_text("Access granted successfully.")
      expect(requester_one.reload.booking_approval).to be(true)
    end

    it "shows nothing for an empty search", js: true, skip_bullet: true do
      open_admin_panel
      find("#user_booking_select + .ts-wrapper .ts-control input").send_keys("Zzzzz")

      expect(page).to have_no_css(".ts-dropdown .option", text: "Rita Requester")
    end
  end
end
