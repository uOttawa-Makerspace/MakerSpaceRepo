# frozen_string_literal: true

require "rails_helper"

# DOM-level characterization of the staff work calendar (/staff/my_calendar,
# FullCalendar timeGridWeek). The server clock is frozen with travel_to (login
# happens inside it so the session is valid). The browser keeps its real clock,
# so the visible week is chosen through the page's own "recall dates on refresh"
# localStorage key (fullCalendarDefaultDateStaffCalendar), set before the page
# under test loads. The week shown is Sun 2027-03-14 .. Sat 2027-03-20, the week
# in which Toronto springs forward.

RSpec.describe "Staff calendar", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space, name: "Calendar Lab") }
  let!(:staff) { create(:user, :staff, space_id: space.id) }

  before do
    create(:staff_space, user: staff, space: space)
    create(:event, space: space, title: "Team sync", event_type: "meeting",
                   start_time: Time.zone.local(2027, 3, 16, 10), end_time: Time.zone.local(2027, 3, 16, 11))
    create(:event, space: space, title: "Sunday opening", event_type: "meeting",
                   start_time: Time.zone.local(2027, 3, 14, 8), end_time: Time.zone.local(2027, 3, 14, 9))
    create(:event, space: space, title: "Next month", event_type: "meeting",
                   start_time: Time.zone.local(2027, 4, 20, 10), end_time: Time.zone.local(2027, 4, 20, 11))
    create(:event, :draft, space: space, title: "Hidden draft", event_type: "meeting",
                           start_time: Time.zone.local(2027, 3, 17, 10), end_time: Time.zone.local(2027, 3, 17, 11))
  end

  around { |ex| travel_to(Time.zone.local(2027, 3, 16, 12)) { ex.run } }

  def show_week_of_march_14
    visit root_path
    page.execute_script("localStorage.fullCalendarDefaultDateStaffCalendar = '2027-03-16T12:00:00.000Z'")
    visit staff_my_calendar_index_path
  end

  # N+1 pinned: see defects D-PERF-SP01 (the JSON feed reads event_assignments per event)
  it "renders the Sunday-to-Saturday week with that week's non-draft events", js: true, skip_bullet: true do
    log_in_as(staff)
    show_week_of_march_14

    expect(page).to have_css("h1", text: "My Work Schedule")
    expect(page).to have_css("#calendar .fc-toolbar-title", text: "Mar 14 – 20, 2027")

    dates = page.all("#calendar th.fc-col-header-cell[data-date]", minimum: 7).map { |th| th[:"data-date"] }
    expect(dates).to eq(%w[2027-03-14 2027-03-15 2027-03-16 2027-03-17 2027-03-18 2027-03-19 2027-03-20])

    expect(page).to have_css(".fc-timegrid-event", text: "Team sync", visible: :all)
    expect(page).to have_css(".fc-timegrid-event", text: "Sunday opening", visible: :all)
    expect(page).to have_css(".fc-timegrid-event", count: 2, visible: :all)
    expect(page).not_to have_css(".fc-event", text: "Next month", visible: :all)
    expect(page).not_to have_css(".fc-event", text: "Hidden draft", visible: :all)
  end

  it "shows the space picker, view switchers and toggle buttons", js: true do
    log_in_as(staff)
    show_week_of_march_14

    expect(page).to have_select("space_id", selected: "Calendar Lab")
    expect(page).to have_button("Go")
    expect(page).to have_css(".fc-timeGridWeek-button", text: /week/i)
    expect(page).to have_css(".fc-dayGridMonth-button", text: /month/i)
    expect(page).to have_css(".fc-toggleOthersShifts-button", text: "Show My Shifts Only")
    expect(page).to have_css(".fc-toggleEventOverlap-button", text: "Enable Event Overlap")
    expect(page).to have_link("View and manage your unavailabilities here", href: "/staff/unavailabilities")
  end

  it "sends a guest to the login page", js: true do
    visit staff_my_calendar_index_path
    expect(page).to have_current_path(%r{\A/login\?back_to=%2Fstaff%2Fmy_calendar})
  end
end
