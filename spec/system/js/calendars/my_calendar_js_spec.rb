# frozen_string_literal: true

require "rails_helper"

# The toolbar toggles, event styling and tooltips of the staff work calendar
# (entrypoints/my_calendar.js). The basic rendering is in
# spec/system/staff_calendar_spec.rb. The week shown is Sun 2027-03-14 .. Sat 2027-03-20.

RSpec.describe "Staff calendar: toolbar and events", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space, name: "Calendar Lab") }
  let!(:staff) { create(:user, :staff, name: "Wanda Worker", space_id: space.id) }
  let!(:other) { create(:user, :staff, name: "Omar Other", space_id: space.id) }

  before do
    create(:staff_space, user: staff, space: space, color: "#cc3300")
    create(:staff_space, user: other, space: space, color: "#0033cc")
    mine = create(:event, space: space, title: "My shift", event_type: "shift", draft: false,
                          description: "Front desk",
                          start_time: Time.zone.local(2027, 3, 16, 10), end_time: Time.zone.local(2027, 3, 16, 12))
    theirs = create(:event, space: space, title: "Their shift", event_type: "shift", draft: false,
                            start_time: Time.zone.local(2027, 3, 17, 10), end_time: Time.zone.local(2027, 3, 17, 12))
    create(:event_assignment, event: mine, user: staff)
    create(:event_assignment, event: theirs, user: other)
  end

  around { |ex| travel_to(Time.zone.local(2027, 3, 16, 12)) { ex.run } }

  def open_calendar
    log_in_as(staff)
    show_week_of_march_14("fullCalendarDefaultDateStaffCalendar", staff_my_calendar_index_path)
    expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 14 – 20, 2027")
    expect(page).to have_css(".fc-timegrid-event", text: "My shift", visible: :all)
  end

  it "shows every shift until the 'show my shifts' button is pressed, then only the user's", js: true, skip_bullet: true do
    open_calendar
    expect(page).to have_css(".fc-timegrid-event", text: "Their shift", visible: :all)

    find(".fc-toggleOthersShifts-button").click

    expect(page).to have_no_css(".fc-timegrid-event", text: "Their shift", visible: :all)
    expect(page).to have_css(".fc-timegrid-event", text: "My shift", visible: :all)
  end

  it "labels the button 'Show My Shifts Only' after the first press and 'Show All Shifts' after the second", js: true, skip_bullet: true do
    open_calendar
    button = ".fc-toggleOthersShifts-button"

    expect(page).to have_css(button, text: "Show My Shifts Only")
    find(button).click
    expect(page).to have_css(button, text: "Show My Shifts Only")
    find(button).click
    expect(page).to have_css(button, text: "Show All Shifts")
    expect(page).to have_css(".fc-timegrid-event", text: "Their shift", visible: :all)
  end

  it "switches event overlap on and remembers it for the next visit", js: true, skip_bullet: true do
    open_calendar
    find(".fc-toggleEventOverlap-button").click
    expect(page).to have_css(".fc-toggleEventOverlap-button", text: "Disable Event Overlap")
    expect(page.evaluate_script("localStorage.fullCalendarEventOverlap")).to eq("true")

    visit staff_my_calendar_index_path
    expect(page).to have_css(".fc-toggleEventOverlap-button", text: "Disable Event Overlap")
  end

  it "remembers the week shown", js: true, skip_bullet: true do
    open_calendar
    find(".fc-next-button").click
    expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 21 – 27, 2027")

    visit staff_my_calendar_index_path
    expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 21 – 27, 2027")
  end

  it "paints an assigned shift with the staff colour and fades it in", js: true, skip_bullet: true do
    open_calendar

    event = find(".fc-timegrid-event", text: "My shift", visible: :all)
    expect(event[:style]).to include("linear-gradient")
    expect(event[:style]).to match(/rgb\(\d+, \d+, \d+\)/)
    expect(page).to have_css(".fc-timegrid-event.fade-in", text: "My shift", visible: :all)
  end

  it "shows the title and description in a tooltip on hover", js: true, skip_bullet: true do
    open_calendar
    find(".fc-timegrid-event", text: "My shift", visible: :all).hover

    expect(page).to have_css(".tooltip", text: "My shift")
    expect(page).to have_css(".tooltip i", text: "Front desk")
  end

  it "switches to the month grid", js: true, skip_bullet: true do
    open_calendar
    find(".fc-dayGridMonth-button").click

    expect(page).to have_css("#calendar .fc-toolbar-title", text: "March 2027")
    expect(page).to have_css(".fc-daygrid-event", text: "My shift", visible: :all)
  end
end
