# frozen_string_literal: true

require "rails_helper"

# The staff work calendar page loads without a console error (the system
# examples fail on any SEVERE browser log entry), whether or not the user has a
# space to show, and moving away from it under Turbo stays clean too.
RSpec.describe "Staff calendar page: console errors", type: :system, skip_bullet: true do
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

  it "shows the calendar and its events for a staff member with a space", js: true do
    staff = create(:user, :staff, space_id: space.id)
    create(:staff_space, user: staff, space: space)
    create(:event, space: space, title: "Team sync", event_type: "meeting",
                   start_time: 1.hour.from_now.beginning_of_hour, end_time: 2.hours.from_now.beginning_of_hour)
    open_calendar_as(staff)
    expect(page).to have_css("#calendar .fc-toolbar-title")
    expect(page).to have_css(".fc-event", text: "Team sync", visible: :all)
  end

  it "stays clean when staff move on to another staff page by link", js: true do
    staff = create(:user, :staff, space_id: space.id)
    create(:staff_space, user: staff, space: space)
    open_calendar_as(staff)
    expect(page).to have_css("#calendar .fc-toolbar-title")
    find_link("View and manage your unavailabilities here").click
    expect(page).to have_current_path("/staff/unavailabilities")
  end
end
