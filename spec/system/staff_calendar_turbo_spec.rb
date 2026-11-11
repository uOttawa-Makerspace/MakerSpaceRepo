# frozen_string_literal: true

require "rails_helper"

# The staff work calendar must be drawn exactly once whether the page is
# entered by a Turbo visit from another staff page or restored by the back
# button from Turbo's page cache.

RSpec.describe "Staff calendar under Turbo navigation", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space, name: "Calendar Lab") }
  let!(:staff) { create(:user, :staff, space_id: space.id) }

  before do
    create(:staff_space, user: staff, space: space)
    create(:event, space: space, title: "Team sync", event_type: "meeting",
                   start_time: Time.zone.local(2026, 11, 10, 10), end_time: Time.zone.local(2026, 11, 10, 11))
  end

  around { |ex| travel_to(Time.zone.local(2026, 11, 11, 12)) { ex.run } }

  def start_on(path)
    log_in_as(staff, to: path)
    expect(page).to have_current_path(path)
  end

  def turbo_visit(path)
    page.execute_script("Turbo.visit(arguments[0])", path)
    expect(page).to have_current_path(path)
  end

  def expect_drawn_once
    expect(page).to have_css("#calendar .fc-toolbar-title")
    expect(page).to have_css(".fc-toggleOthersShifts-button", count: 1)
    expect(page).to have_css(".fc-timegrid-event", text: "Team sync", visible: :all)
    expect(page).to have_css("#calendar .fc-toolbar", count: 1)
    expect(page).to have_css("#calendar .fc-timegrid-event", count: 1, visible: :all)
  end

  it "draws the calendar after a Turbo visit from another staff page", js: true, skip_bullet: true do
    start_on(staff_dashboard_index_path)
    turbo_visit(staff_my_calendar_index_path)
    expect_drawn_once
  end

  it "draws the calendar once when the back button restores it from the cache", js: true, skip_bullet: true do
    start_on(staff_my_calendar_index_path)
    expect_drawn_once
    turbo_visit(staff_dashboard_index_path)
    page.go_back
    expect(page).to have_current_path(staff_my_calendar_index_path)
    expect_drawn_once
  end
end
