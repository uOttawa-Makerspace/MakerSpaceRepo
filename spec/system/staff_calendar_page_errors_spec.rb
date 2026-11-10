# frozen_string_literal: true

require "rails_helper"

# The staff work calendar page loads without a console error (the system
# examples fail on any SEVERE browser log entry), whether or not the user has a
# space to show, and moving away from it under Turbo stays clean too.
RSpec.describe "Staff calendar page: console errors", type: :system, skip_bullet: true do
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space, name: "Calendar Lab") }

  def open_calendar_as(user)
    log_in_as(user, to: staff_my_calendar_index_path)
    expect(page).to have_css("h1", text: "My Work Schedule")
  end

  it "shows the notice for an admin with no staff space", js: true do
    open_calendar_as(create(:user, :admin, space_id: nil))
    expect(page).to have_css(".alert-info", text: "not assigned to any space")
    expect(page).to have_no_css("#calendar")
  end

  it "shows the notice for an admin whose space_id is set but who has no staff space rows", js: true do
    open_calendar_as(create(:user, :admin, space_id: space.id))
    expect(page).to have_css(".alert-info", text: "not assigned to any space")
  end

  # The server clock is frozen; the browser keeps its real clock, so the visible
  # week is chosen through the page's own remembered-date key, as in
  # spec/system/staff_calendar_spec.rb. Wed 2027-03-17 is the middle of the week
  # Sun 03-14 .. Sat 03-20, whatever the server and browser zones.
  it "shows the calendar and its events for a staff member with a space", js: true do
    travel_to(Time.zone.local(2027, 3, 17, 12)) do
      staff = create(:user, :staff, space_id: space.id)
      create(:staff_space, user: staff, space: space)
      create(:event, space: space, title: "Team sync", event_type: "meeting",
                     start_time: Time.zone.local(2027, 3, 17, 10), end_time: Time.zone.local(2027, 3, 17, 11))
      log_in_as(staff, to: staff_my_calendar_index_path,
                       local_storage: { fullCalendarDefaultDateStaffCalendar: "2027-03-17T12:00:00.000Z" })
      expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 14 – 20, 2027")
      expect(page).to have_css(".fc-timegrid-event", text: "Team sync", visible: :all)
    end
  end

  # A Turbo visit keeps the document, so the calendar script's turbo:load
  # listener runs again on the destination page, which has no calendar.
  it "stays clean when Turbo moves staff on to another staff page", js: true do
    staff = create(:user, :staff, space_id: space.id)
    create(:staff_space, user: staff, space: space)
    open_calendar_as(staff)
    expect(page).to have_css("#calendar .fc-toolbar-title")
    page.execute_script("Turbo.visit('/staff/unavailabilities')")
    expect(page).to have_css("h1", text: "My Unavailabilities")
    expect(page).to have_no_css("#calendar")
  end
end
