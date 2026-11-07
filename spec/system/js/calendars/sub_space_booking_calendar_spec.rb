# frozen_string_literal: true

require "rails_helper"

# The room booking calendar and its modal (entrypoints/sub_space_booking.js):
# create one booking or a series, conflicts and limits, edit, update, delete.
# The server clock is fixed (:booking_clock, Dec 2026); the week shown is the
# one containing 2027-03-16 (the page's own ?start= parameter).

RSpec.describe "Sub-space booking calendar", :booking_clock, type: :system do
  before do
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
  end

  let(:space) { create(:space, name: "Maker Hall") }
  let(:subspace) { create(:sub_space, space: space, name: "Laser Room", approval_required: false) }
  let(:user) { create(:user, :regular_user, name: "Reggie Regular", booking_approval: true) }
  let(:admin) { create(:user, :admin, name: "Ada Admin", booking_approval: true) }
  let(:eastern) { ActiveSupport::TimeZone["Eastern Time (US & Canada)"] }

  def open_calendar(who = user)
    log_in_as(who)
    visit sub_space_booking_index_path(room: subspace.id, start: "2027-03-16")
    expect(page).to have_css("#booked-calendar .fc-view")
  end

  # The date inputs are read-only flatpickr fields: set them through the
  # picker the page created for them.
  def pick(id, value)
    page.execute_script("document.getElementById('#{id}')._flatpickr.setDate('#{value}', true)")
  end

  def open_book_modal
    find(".fc-book-button").click
    expect(page).to have_css("#bookModal.show", visible: :all)
  end

  def fill_booking(name: "Laser practice", description: "Cutting acrylic", start: "2027-03-16 10:00", finish: "2027-03-16 11:00")
    fill_in "book-name", with: name
    fill_in "book-description", with: description
    pick("book-start", start)
    pick("book-end", finish)
  end

  def stored(booking)
    booking.reload.start_time.in_time_zone(eastern).strftime("%Y-%m-%d %H:%M")
  end

  describe "opening the modal" do
    it "opens a new-booking modal from the Book button with only the Book action", js: true, skip_bullet: true do
      open_calendar
      open_book_modal

      expect(page).to have_css("#bookingModalLabel", text: "New Booking")
      expect(page).to have_css("#bookSave", visible: :visible)
      expect(page).to have_css("#bookUpdate", visible: :hidden)
      expect(page).to have_css("#bookDelete", visible: :hidden)
      expect(page).to have_css("#subspace", visible: :hidden)
      expect(page).to have_css("#book-recurring", visible: :visible)
      expect(page).to have_css("#book-recurring-end", visible: :hidden)
    end

    it "fills the dates from a range dragged on the calendar", js: true, skip_bullet: true do
      open_calendar
      slot = find(".fc-timegrid-col[data-date='2027-03-17'] .fc-timegrid-col-frame")
      page.driver.browser.action.move_to(slot.native).click_and_hold.move_by(0, 60).release.perform

      expect(page).to have_css("#bookModal.show", visible: :all)
      expect(page.evaluate_script("document.getElementById('book-start').value")).to start_with("2027-03-17 ")
      expect(page.evaluate_script("document.getElementById('book-end').value")).to start_with("2027-03-17 ")
    end

    it "shows the recurring fields only while the recurring box is ticked", js: true, skip_bullet: true do
      open_calendar
      open_book_modal
      check "book-recurring"

      expect(page).to have_css("#book-recurring-end-label", visible: :visible)
      expect(page).to have_css("#book-recurring-type", visible: :visible)
      uncheck "book-recurring"
      expect(page).to have_css("#book-recurring-type", visible: :hidden)
    end

    it "closes with Close and with the X, clearing what was typed", js: true, skip_bullet: true do
      open_calendar
      open_book_modal
      fill_in "book-name", with: "Draft"
      click_button "bookCancel"
      expect(page).to have_no_css("#bookModal.show", visible: :all)

      open_book_modal
      expect(find("#book-name").value).to eq("")
      find("#bookClose").click
      expect(page).to have_no_css("#bookModal.show", visible: :all)
    end
  end

  # The browser logs the 422 answers of refused bookings, and a 404 after a
  # delete (the page follows the redirect with a JSON request); both are
  # allowlisted in spec/support/js_error_allowlist.rb.
  describe "booking a room" do
    it "books a single slot and shows it on the calendar", js: true, skip_bullet: true do
      open_calendar
      open_book_modal
      fill_booking
      click_button "bookSave"

      expect(page).to have_no_css("#bookModal.show", visible: :all)
      expect(page).to have_css(".fc-timegrid-event", text: "Laser practice - Cutting acrylic", visible: :all)
      booking = SubSpaceBooking.find_by!(name: "Laser practice")
      expect(booking.user).to eq(user)
      expect(booking.sub_space).to eq(subspace)
      expect(stored(booking)).to eq("2027-03-16 10:00")
      expect(booking.sub_space_booking_status.booking_status).to eq(@approved_status)
    end

    it "shows the end-before-start message and sends nothing", js: true, skip_bullet: true do
      open_calendar
      open_book_modal
      fill_booking(start: "2027-03-16 11:00", finish: "2027-03-16 10:00")
      click_button "bookSave"

      expect(page).to have_css("#end-date-validation", visible: :visible)
      expect(page).to have_css("#book-end + input.is-invalid, input.is-invalid", visible: :all)
      expect(SubSpaceBooking.count).to eq(0)
      expect(page).to have_css("#bookModal.show", visible: :all)
    end

    it "marks the name field when the server says it is blank, and keeps the modal open", js: true, skip_bullet: true do
      open_calendar
      open_book_modal
      fill_booking(name: "")
      click_button "bookSave"

      expect(page).to have_css("#book-name.is-invalid")
      expect(page).to have_css("#book-name + .invalid-feedback", text: "This field is required.")
      expect(page).to have_css("#bookModal.show", visible: :all)
      expect(page).to have_no_css("#bookSave[disabled]")
      expect(SubSpaceBooking.count).to eq(0)
    end

    it "books a weekly series up to the end date", js: true, skip_bullet: true do
      open_calendar
      open_book_modal
      fill_booking
      check "book-recurring"
      pick("book-recurring-end", "2027-03-30")
      select "Weekly", from: "book-recurring-type"
      click_button "bookSave"

      expect(page).to have_no_css("#bookModal.show", visible: :all)
      expect(page).to have_css(".fc-timegrid-event", text: "Laser practice", visible: :all)
      bookings = SubSpaceBooking.where(name: "Laser practice").order(:start_time)
      expect(bookings.map { |b| stored(b) }).to eq(["2027-03-16 10:00", "2027-03-23 10:00", "2027-03-30 10:00"])
      expect(bookings.map(&:recurring_booking_id).uniq.size).to eq(1)
    end

    it "refuses a series without an end date", js: true, skip_bullet: true do
      open_calendar
      open_book_modal
      fill_booking
      check "book-recurring"
      click_button "bookSave"

      expect(page).to have_css("#bookModal.show", visible: :all)
      expect(SubSpaceBooking.count).to eq(0)
      expect(page).to have_no_css("#bookSave[disabled]")
    end

    it "shows a toast and closes the modal when the slot is blocked", js: true, skip_bullet: true do
      create(:sub_space_booking, sub_space: subspace, user: admin, name: "Maintenance", blocking: true, public: true,
                                 start_time: eastern.local(2027, 3, 16, 9), end_time: eastern.local(2027, 3, 16, 12))
      open_calendar
      open_book_modal
      fill_booking
      click_button "bookSave"

      expect(page).to have_css("#booking_toast.show", text: "Booking failed")
      expect(page).to have_css("#toast_text", text: "This time slot is already booked.")
      expect(page).to have_no_css("#bookModal.show", visible: :all)
      expect(SubSpaceBooking.where(name: "Laser practice")).to be_empty
    end

    it "shows a toast when the booking is longer than the room allows", js: true, skip_bullet: true do
      subspace.update!(maximum_booking_duration: 1)
      open_calendar
      open_book_modal
      fill_booking(finish: "2027-03-16 13:00")
      click_button "bookSave"

      expect(page).to have_css("#booking_toast.show", text: "Booking failed")
      expect(page).to have_css("#toast_text", text: "more than 1")
      expect(SubSpaceBooking.where(name: "Laser practice")).to be_empty
    end

    it "keeps the occurrences that fit and says so when part of a series is blocked", js: true, skip_bullet: true do
      create(:sub_space_booking, sub_space: subspace, user: admin, name: "Maintenance", blocking: true, public: true,
                                 start_time: eastern.local(2027, 3, 23, 9), end_time: eastern.local(2027, 3, 23, 12))
      open_calendar
      open_book_modal
      fill_booking
      check "book-recurring"
      pick("book-recurring-end", "2027-03-30")
      click_button "bookSave"

      expect(page).to have_css("#booking_toast.show", text: "Booking partly done")
      expect(page).to have_no_css("#bookModal.show", visible: :all)
      expect(SubSpaceBooking.where(name: "Laser practice").count).to eq(2)
    end

    it "lets an admin block the room", js: true, skip_bullet: true do
      open_calendar(admin)
      open_book_modal
      fill_booking(name: "Closed")
      check "book-blocking"
      click_button "bookSave"

      expect(page).to have_no_css("#bookModal.show", visible: :all)
      expect(SubSpaceBooking.find_by!(name: "Closed").blocking).to be(true)
    end
  end

  describe "an existing booking" do
    let!(:booking) do
      create(:sub_space_booking, sub_space: subspace, user: admin, name: "Team lab", description: "Weekly",
                                 start_time: eastern.local(2027, 3, 16, 10), end_time: eastern.local(2027, 3, 16, 11)).tap do |b|
        b.sub_space_booking_status.update!(booking_status: @approved_status)
      end
    end

    def open_booking(title = "Team lab")
      expect(page).to have_css(".fc-timegrid-event", text: title, visible: :all)
      find(".fc-timegrid-event", text: title, visible: :all).click
      expect(page).to have_css("#bookModal.show", visible: :all)
    end

    it "opens an update modal filled from the booking for an admin", js: true, skip_bullet: true do
      open_calendar(admin)
      open_booking

      expect(page).to have_css("#bookingModalLabel", text: "Update Booking")
      expect(find("#book-name").value).to eq("Team lab")
      expect(find("#book-description").value).to eq("Weekly")
      expect(find("#subspace").value).to eq(subspace.id.to_s)
      expect(page).to have_css("#bookUpdate", visible: :visible)
      expect(page).to have_css("#bookSave", visible: :hidden)
      expect(page).to have_css("#bookDelete", visible: :visible)
      expect(page).to have_css("#book-recurring", visible: :hidden)
      expect(find("#sub_space_booking_id", visible: :all).value).to eq(booking.id.to_s)
    end

    it "saves a changed name and time", js: true, skip_bullet: true do
      open_calendar(admin)
      open_booking
      fill_in "book-name", with: "Team lab (moved)"
      pick("book-start", "2027-03-16 14:00")
      pick("book-end", "2027-03-16 15:00")
      click_button "bookUpdate"

      expect(page).to have_no_css("#bookModal.show", visible: :all)
      expect(page).to have_css(".fc-timegrid-event", text: "Team lab (moved)", visible: :all)
      expect(booking.reload.name).to eq("Team lab (moved)")
      expect(stored(booking)).to eq("2027-03-16 14:00")
    end

    it "rejects an end before the start without sending", js: true, skip_bullet: true do
      open_calendar(admin)
      open_booking
      pick("book-start", "2027-03-16 15:00")
      pick("book-end", "2027-03-16 14:00")
      click_button "bookUpdate"

      expect(page).to have_css("#end-date-validation", visible: :visible)
      expect(stored(booking)).to eq("2027-03-16 10:00")
    end

    it "deletes the booking after confirming", js: true, skip_bullet: true do
      open_calendar(admin)
      open_booking
      accept_confirm("Delete this booking?") { click_button "bookDelete" }

      expect(page).to have_no_css(".fc-timegrid-event", text: "Team lab", visible: :all)
      expect(SubSpaceBooking.exists?(booking.id)).to be(false)
    end

    it "keeps the booking when the confirmation is refused", js: true, skip_bullet: true do
      open_calendar(admin)
      open_booking
      dismiss_confirm("Delete this booking?") { click_button "bookDelete" }

      expect(SubSpaceBooking.exists?(booking.id)).to be(true)
      expect(page).to have_css("#bookModal.show", visible: :all)
    end

    it "shows 'Space Booked' to a user for somebody else's private booking, and a click asks for nothing and shows no error", js: true, skip_bullet: true do
      open_calendar(user)
      expect(page).to have_css(".fc-timegrid-event", text: "Space Booked", visible: :all)
      page.execute_script(<<~JS)
        window.detailRequests = [];
        const realFetch = window.fetch;
        window.fetch = (url, ...rest) => { window.detailRequests.push(String(url)); return realFetch(url, ...rest); };
      JS
      find(".fc-timegrid-event", text: "Space Booked", visible: :all).click

      # the click handler runs synchronously, so a request would already be recorded
      expect(page.evaluate_script("window.detailRequests")).to eq([])
      expect(page).to have_no_css("#bookModal.show, #booking_toast.show", visible: :all)
    end

    # The browser logs the 500 itself, inside this example.
    it "tells the admin when a booking's details cannot be loaded", js: true, skip_bullet: true, js_errors: :allow do
      allow_any_instance_of(SubSpaceBookingController).to receive(:get_sub_space_booking) { |c| c.head :internal_server_error }
      open_calendar(admin)
      expect(page).to have_css(".fc-timegrid-event", text: "Team lab", visible: :all)
      find(".fc-timegrid-event", text: "Team lab", visible: :all).click

      expect(page).to have_css("#booking_toast.show", text: "This booking could not be opened.", visible: :all)
      expect(page).to have_no_css("#bookModal.show", visible: :all)
    end
  end

  describe "a recurring booking" do
    let!(:series) do
      recurring = RecurringBooking.create!
      [eastern.local(2027, 3, 16, 10), eastern.local(2027, 3, 23, 10)].map do |start|
        create(:sub_space_booking, sub_space: subspace, user: admin, name: "Club night", recurring_booking_id: recurring.id,
                                   start_time: start, end_time: start + 1.hour).tap do |b|
          b.sub_space_booking_status.update!(booking_status: @approved_status)
        end
      end
    end

    def open_first
      expect(page).to have_css(".fc-timegrid-event", text: "Club night", visible: :all)
      find(".fc-timegrid-event", text: "Club night", visible: :all, match: :first).click
      expect(page).to have_css("#bookModal.show", visible: :all)
    end

    it "offers the two delete choices instead of the single delete", js: true, skip_bullet: true do
      open_calendar(admin)
      open_first

      expect(page).to have_css("#bookDelete", visible: :hidden)
      expect(page).to have_css("#bookDeleteRecurringDropdown", visible: :visible)
    end

    it "deletes only the clicked occurrence with 'This only'", js: true, skip_bullet: true do
      open_calendar(admin)
      open_first
      click_button "Delete..."
      accept_confirm("Delete this booking?") { click_button "bookRecurringDeleteOne" }

      expect(page).to have_no_css("#bookModal.show", visible: :all)
      expect(SubSpaceBooking.where(name: "Club night").count).to eq(1)
    end

    it "deletes the clicked and later occurrences with 'This and rest'", js: true, skip_bullet: true do
      open_calendar(admin)
      open_first
      click_button "Delete..."
      accept_confirm("Delete this and all remaining occurrences?") { click_button "bookRecurringDeleteRest" }

      expect(page).to have_no_css(".fc-timegrid-event", text: "Club night", visible: :all)
      expect(SubSpaceBooking.where(name: "Club night")).to be_empty
    end
  end
end
