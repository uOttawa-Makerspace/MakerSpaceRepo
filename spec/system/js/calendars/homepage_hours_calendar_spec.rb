# frozen_string_literal: true

require "rails_helper"

# The opening-hours calendar of the home page and the /hours page
# (entrypoints/fullcalendar_setup_homepage.js). The hours come from the
# open-hours calendar of a space (an ICS feed, stubbed here).

RSpec.describe "Opening hours calendar", type: :system do
  let!(:space) { create(:space, name: "Makerspace Alpha") }
  let(:url) { "https://feeds.example.org/hours.ics" }
  let(:daily_hours) do
    ics_feed(uid: "hours-1", summary: "Open", starts: Time.utc(2026, 1, 5, 14), ends: Time.utc(2026, 1, 5, 22),
             rrule: "FREQ=DAILY")
  end

  def stub_hours(body = daily_hours)
    StaffNeededCalendar.create!(calendar_url: url, role: "open_hours", space_id: space.id, color: "#117733")
    allow(IcsFetcher).to receive(:get).with(url, any_args).and_return(body)
  end

  it "says so when no space has published opening hours", js: true, skip_bullet: true do
    visit root_path

    expect(page).to have_css("#calendar", text: "No open hours available // Aucune heure d'ouverture disponible")
    expect(page).to have_no_css("#calendar .fc-view")
  end

  it "shows five days on a wide window with a filter for each space", js: true, skip_bullet: true do
    stub_hours
    visit root_path

    expect(page).to have_css("#calendar th.fc-col-header-cell[data-date]", count: 5)
    expect(page).to have_css("#calendar .fc-timegrid-event", text: "Open", minimum: 1, visible: :all)
    expect(page).to have_css("#filters label", text: "Makerspace Alpha")
    expect(page).to have_css("#filters input[type=checkbox]:checked", visible: :all, count: 1)
  end

  it "hides the events of a space when its filter is cleared and shows them when it is ticked again", js: true, skip_bullet: true do
    stub_hours
    visit root_path
    expect(page).to have_css("#calendar .fc-timegrid-event", minimum: 1, visible: :all)
    box = find("#filters input[type=checkbox]", visible: :all)

    box.uncheck(allow_label_click: true)
    expect(page).to have_no_css("#calendar .fc-timegrid-event", visible: :all)

    box.check(allow_label_click: true)
    expect(page).to have_css("#calendar .fc-timegrid-event", minimum: 1, visible: :all)
  end

  it "steps through the days with the previous and next buttons", js: true, skip_bullet: true do
    stub_hours
    visit root_path
    first_day = find("#calendar th.fc-col-header-cell[data-date]", match: :first)[:"data-date"]

    find("#calendar .fc-next-button").click
    expect(page).to have_no_css("#calendar th[data-date='#{first_day}']")
    find("#calendar .fc-prev-button").click
    expect(page).to have_css("#calendar th[data-date='#{first_day}']")
  end

  it "shows a full week with an all-day row on the hours page", js: true, skip_bullet: true do
    stub_hours
    visit hours_path

    expect(page).to have_css("#calendar th.fc-col-header-cell[data-date]", count: 7)
    expect(page).to have_css("#calendar .fc-daygrid-body")
  end

  it "shows fewer days when the window is narrow, and more again when it widens", js: true, skip_bullet: true do
    stub_hours
    visit root_path
    expect(page).to have_css("#calendar th.fc-col-header-cell[data-date]", count: 5)

    page.driver.browser.manage.window.resize_to(800, 900)
    expect(page).to have_css("#calendar th.fc-col-header-cell[data-date]", count: 2)
    page.driver.browser.manage.window.resize_to(1600, 1000)
    expect(page).to have_css("#calendar th.fc-col-header-cell[data-date]", count: 5)
  end

  it "shows three days on the hours page when the window is narrow", js: true, skip_bullet: true do
    stub_hours
    page.driver.browser.manage.window.resize_to(800, 900)
    visit hours_path

    expect(page).to have_css("#calendar th.fc-col-header-cell[data-date]", count: 3)
    page.driver.browser.manage.window.resize_to(1600, 1000)
    expect(page).to have_css("#calendar th.fc-col-header-cell[data-date]", count: 7)
  end

  it "builds the calendar again when the page is left and revisited", js: true, skip_bullet: true do
    stub_hours
    visit root_path
    expect(page).to have_css("#calendar .fc-view", count: 1)

    visit hours_path
    expect(page).to have_css("#calendar th.fc-col-header-cell[data-date]", count: 7)
    visit root_path
    expect(page).to have_css("#calendar .fc-view", count: 1)
    expect(page).to have_css("#filters input[type=checkbox]", count: 1, visible: :all)
  end

  it "shows no calendar when the hours cannot be loaded", js: true, skip_bullet: true do
    allow_any_instance_of(StaticPagesController).to receive(:open_hours) { |controller| controller.head :internal_server_error }
    visit root_path

    expect(page).to have_css("#calendar", visible: :all)
    expect(page).to have_no_css("#calendar .fc-view", visible: :all)
    expect(page).to have_no_css("#filters input", visible: :all)
  end

  it "leaves the home page and returns with one calendar and one set of filters", js: true, skip_bullet: true do
    stub_hours
    visit root_path
    expect(page).to have_css("#filters input[type=checkbox]", count: 1, visible: :all)
    click_link href: hours_path
    expect(page).to have_current_path(hours_path)
    expect(page).to have_css("#calendar th.fc-col-header-cell[data-date]", count: 7)
    page.go_back

    expect(page).to have_css("#calendar .fc-view", count: 1)
    expect(page).to have_css("#filters input[type=checkbox]", count: 1, visible: :all)
  end
end
