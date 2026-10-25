# frozen_string_literal: true

require "rails_helper"

# End-to-end booking journey through the real calendar UI: the user opens the
# FullCalendar "Book" modal, fills it (flatpickr fields set through the widget's
# own API, there is no typing into the read-only alt input), saves; the admin
# approves in the Admin Panel tab; the user sees the booking approved.
RSpec.describe "Journey: space booking", type: :system do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
    ActionMailer::Base.deliveries.clear
  end

  let(:manager) { create(:user, :admin, booking_approval: true) }
  let(:space) { create(:space).tap { |s| s.space_managers << manager } }
  let(:subspace) { create(:sub_space, space: space, name: "Journey Room", approval_required: true) }
  let!(:user) { create(:user, :regular_user, booking_approval: true) }
  let!(:admin) { manager }
  # Tomorrow 10:00-11:00 (wall clock, as the modal's flatpickr submits it)
  let(:day) { Date.current + 1 }

  def stamp(date, hour)
    format("%<d>s %<h>02d:00", d: date.strftime("%Y-%m-%d"), h: hour)
  end

  def open_booking_modal(date)
    visit sub_space_booking_index_path(room: subspace.id, start: date.iso8601)
    expect(page).to have_css("#booked-calendar .fc-toolbar")
    find(".fc-book-button").click
    expect(page).to have_css("#bookModal.show", visible: :all)
    expect(page).to have_css("#bookingModalLabel", text: "New Booking")
  end

  def set_picker(id, value)
    page.execute_script("document.getElementById(arguments[0])._flatpickr.setDate(arguments[1], true)", id, value)
  end

  def fill_booking_modal(name:, description:, start_hour: 10, end_hour: 11, recurring_until: nil)
    fill_in "book-name", with: name
    fill_in "book-description", with: description
    set_picker("book-start", stamp(day, start_hour))
    set_picker("book-end", stamp(day, end_hour))
    if recurring_until
      check "book-recurring"
      select "Weekly", from: "book-recurring-type"
      set_picker("book-recurring-end", recurring_until.strftime("%Y-%m-%d"))
    end
  end

  it "user books a single slot -> admin approves in the admin panel -> user sees it approved" do
    as_actor(:user) do
      log_in_as(user)
      open_booking_modal(day)
      fill_booking_modal(name: "Robot team", description: "Weekly sync")
      click_button "bookSave"
      expect(page).to have_no_css("#bookModal.show", visible: :all)
      # the calendar refetches and shows the (pending) booking
      expect(page).to have_css(".fc-event", text: "Robot team - Weekly sync (Pending)")
    end

    booking = SubSpaceBooking.order(:id).last
    expect(booking.user).to eq(user)
    expect(booking.name).to eq("Robot team")
    expect(booking.sub_space).to eq(subspace)
    expect(booking.sub_space_booking_status.booking_status).to eq(@pending_status)
    needs = deliver_mail.select { |m| m.subject == "Booking needs approval" }
    expect(needs.map(&:to)).to eq([[manager.email]])

    as_actor(:admin) do
      log_in_as(admin)
      visit sub_space_booking_index_path(room: subspace.id)
      find("#booking-admin-tab-btn").click
      expect(page).to have_css("#pendingBody", text: "Robot team")
      within(:xpath, "//tr[.//strong[contains(.,'Robot team')] or contains(.,'Robot team')][.//button[contains(.,'Approve')]]") do
        click_button "Approve"
      end
      expect(page).to have_text("Booking for Journey Room approved successfully.")
    end

    booking.reload
    expect(booking.sub_space_booking_status.booking_status).to eq(@approved_status)
    expect(booking.approved_by).to eq(admin)
    approved = deliver_mail.select { |m| m.subject == "Booking approved" }
    expect(approved.map(&:to)).to eq([[user.email]])

    as_actor(:user) do
      visit sub_space_booking_index_path(room: subspace.id, start: day.iso8601)
      expect(page).to have_css(".fc-event", text: "Robot team - Weekly sync")
      expect(page).to have_no_css(".fc-event", text: "(Pending)")
      find("#booking-tab-btn").click
      within("#my-booking-table") do
        expect(page).to have_text("Robot team")
        expect(page).to have_css(".badge", text: "Approved")
      end
    end
  end

  it "user books a weekly recurring series -> admin approves all in one click" do
    as_actor(:user) do
      log_in_as(user)
      open_booking_modal(day)
      fill_booking_modal(name: "Club night", description: "Recurring", recurring_until: day + 15)
      click_button "bookSave"
      expect(page).to have_no_css("#bookModal.show", visible: :all)
      expect(page).to have_css(".fc-event", text: "Club night - Recurring (Pending)")
    end

    bookings = SubSpaceBooking.where(name: "Club night").order(:start_time)
    # WART(D-E2E03): the series loop books one occurrence AFTER the chosen
    # recurring end date (day+21 for an end of day+15).
    expect(bookings.count).to eq(4)
    expect(bookings.map(&:recurring_booking_id).uniq.size).to eq(1)
    expect(bookings.map { |b| b.start_time.to_date }).to eq([day, day + 7, day + 14, day + 21])

    as_actor(:admin) do
      log_in_as(admin)
      visit sub_space_booking_index_path(room: subspace.id)
      find("#booking-admin-tab-btn").click
      expect(page).to have_css("#pendingBody", text: "Club night")
      click_button title: "Approve All"
      expect(page).to have_text("Bookings approved successfully.")
    end
    bookings.each do |b|
      expect(b.reload.sub_space_booking_status.booking_status).to eq(@approved_status)
    end
    approved = deliver_mail.select { |m| m.subject == "Booking approved" }
    expect(approved.map(&:to)).to eq([[user.email]] * 4)
  end

  it "rejects a booking that overlaps a blocking booking (server 422; the UI shows no toast, D-E2E04)" do
    # The overlap check compares the literal wall clock against stored rows, so
    # it only fires for rows that store the literal wall (legacy/factory rows,
    # offset 0); see the D-B06 example below for the UI-created case.
    blocker = create(:sub_space_booking, sub_space: subspace, user: admin, name: "Maintenance",
                                         description: "closed", blocking: true,
                                         start_time: DateTime.parse(stamp(day, 9)),
                                         end_time: DateTime.parse(stamp(day, 12)))
    blocker.sub_space_booking_status.update!(booking_status: @approved_status)

    as_actor(:user, allow_console: [%r{/sub_space_booking - Failed to load resource: .* 422}]) do
      log_in_as(user)
      open_booking_modal(day)
      fill_booking_modal(name: "Sneaky", description: "overlap")
      click_button "bookSave"
      # The server answers 422 "TimeSlot This time slot is already booked." but
      # WART(D-E2E04): the page JS calls the global `bootstrap.Toast`, which is
      # not defined (D-JS02), inside a promise whose .catch swallows the error:
      # no toast, and the modal stays open with the Book button re-enabled.
      expect(page).to have_css("#bookSave:not([disabled])")
      expect(page).to have_css("#bookModal.show", visible: :all)
      expect(page).to have_no_css("#booking_toast.show")
      expect(page.evaluate_script("typeof bootstrap")).to eq("undefined")
    end
    expect(SubSpaceBooking.where(name: "Sneaky")).to be_empty
    expect(SubSpaceBooking.where(sub_space: subspace)).to contain_exactly(blocker)
  end

  it "pinned: a blocking booking made through the UI does not stop an overlapping UI booking (D-B06)" do
    as_actor(:admin) do
      log_in_as(admin)
      open_booking_modal(day)
      fill_booking_modal(name: "Maintenance", description: "closed")
      check "book-blocking"
      click_button "bookSave"
      expect(page).to have_no_css("#bookModal.show", visible: :all)
      expect(page).to have_css(".fc-event", text: "Maintenance")
    end
    blocker = SubSpaceBooking.find_by!(name: "Maintenance")
    expect(blocker.blocking).to be(true)
    expect(blocker.sub_space_booking_status.booking_status).to eq(@approved_status)

    as_actor(:user) do
      log_in_as(user)
      open_booking_modal(day)
      fill_booking_modal(name: "Sneaky", description: "overlap")
      click_button "bookSave"
      expect(page).to have_no_css("#bookModal.show", visible: :all)
      expect(page).to have_css(".fc-event", text: "Sneaky - overlap (Pending)")
    end
    # WART(D-B06): both rows are stored shifted by the app zone offset while
    # the overlap query uses the literal wall, so the conflict is missed.
    expect(SubSpaceBooking.where(name: "Sneaky").count).to eq(1)
  end
end
