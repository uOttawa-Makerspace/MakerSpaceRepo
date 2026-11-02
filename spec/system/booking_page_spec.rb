# frozen_string_literal: true

require "rails_helper"

# Look-and-feel characterization for the booking page
# (sub_space_booking#index with a room picked). Runs headless chromium and a
# REAL login (see spec/support/auth_helpers.rb — log_in_as drives the login
# view rather than shimming the session).

RSpec.describe "Booking page look-and-feel", type: :system do
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
  let(:user) { create(:user, :regular_user, booking_approval: true) }

  it "approved users see the tabs, legend, calendar and booking modal" do
    log_in_as(user)

    visit sub_space_booking_index_path(room: subspace.id)

    # Bootstrap tab chrome (index.html.erb) — one tab per role. NOTE: the
    # tab buttons are styled `text-uppercase`; Chromium's innerText (which
    # Capybara reads for `text:` filters) reports the UPPERCASE form.
    expect(page).to have_css("ul#booking-tab-list.nav.nav-tabs")
    expect(page).to have_css("#booking-calendar-tab-btn", text: "BOOK ROOM")
    expect(page).to have_css("#booking-tab-btn", text: "MY BOOKINGS")
    expect(page).not_to have_css("#booking-admin-tab-btn") # not admin

    # Calendar panel: legend + FullCalendar mount + the modal partial present
    expect(page).to have_css("h2", text: "Event Legend")
    legend = page.find('.col-md-2 h2', text: 'Event Legend').first(:xpath, '..')
    expect(legend).to have_text("Your Pending Bookings")
    expect(legend).to have_text("Your Confirmed Bookings")
    expect(legend).to have_text("Other Pending Bookings")
    expect(legend).to have_text("Other Confirmed Bookings")
    expect(legend).to have_text("Blocking Bookings")

    expect(page).to have_css("#booked-calendar")
    expect(page).to have_css("#bookModal", visible: :all)
    expect(page).to have_text("#{subspace.name} Calendar")
    expect(page).to have_css("#book-name[placeholder='e.g., John Doe, uoRover']", visible: :all)
    expect(page).to have_css("#book-description", visible: :all)
    expect(page).to have_css("#book-start", visible: :all)
    expect(page).to have_css("#book-end", visible: :all)
    expect(page).to have_css("#book-recurring", visible: :all)
    expect(page).to have_css("#book-recurring-type", visible: :all)
    # #book-blocking is inside <% if current_user.admin? %>: regular users
    # don't even get a hidden copy of it
    expect(page).not_to have_css("#book-blocking")
    expect(page).to have_css("#bookSave", visible: :all)
  end

  it "admins additionally get the Admin Panel tab" do
    admin = create(:user, :admin, booking_approval: true)
    log_in_as(admin)
    visit sub_space_booking_index_path(room: subspace.id)

    expect(page).to have_css("#booking-admin-tab-btn", text: "ADMIN PANEL")
    expect(page).to have_css("#pending-accordion", visible: :all)
    # admin-only blocking checkbox lives in the booking modal
    expect(page).to have_css("#book-blocking", visible: :all)
  end

  it "unapproved visitors get the access-request panel instead of tabs" do
    unapproved = create(:user, :regular_user, booking_approval: false)
    log_in_as(unapproved)
    visit sub_space_booking_index_path(room: subspace.id)

    expect(page).not_to have_css("#booking-tab-list")
    expect(page).to have_text("Request Booking Access")
    # identity radio set + reason textarea (the PUT request_access form)
    expect(page).to have_field("identity", with: "JMTS")
    expect(page).to have_field("comments")
    expect(page).to have_css("#comments-container")
  end

  it "users with a pending access request see the pending alert" do
    unapproved = create(:user, :regular_user, booking_approval: false)
    UserBookingApproval.create!(user: unapproved, identity: "Other",
                                approved: false, comments: "please",
                                date: Date.today)
    log_in_as(unapproved)
    visit sub_space_booking_index_path(room: subspace.id)

    expect(page).to have_text("Access Pending")
    expect(page).to have_text(
      "Your request to access MakerRoom is currently pending approval."
    )
  end
end
