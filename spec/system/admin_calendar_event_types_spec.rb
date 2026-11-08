# frozen_string_literal: true

require "rails_helper"

# The event-type checkboxes in the admin calendar sidebar (Training, Meeting,
# ...) show and hide events of that type. The week shown is Sun 2027-03-14 ..
# Sat 2027-03-20, chosen through the page's own "recall dates" localStorage key.

RSpec.describe "Admin calendar event types", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space, name: "Calendar Lab") }
  let!(:admin) { create(:user, :admin, space_id: space.id) }

  before do
    create(:staff_space, user: admin, space: space)
    create(:event, :training, space: space, title: "Soldering training",
                              start_time: Time.zone.local(2027, 3, 16, 9), end_time: Time.zone.local(2027, 3, 16, 10))
    create(:event, :training, space: space, title: "Laser training",
                              start_time: Time.zone.local(2027, 3, 17, 9), end_time: Time.zone.local(2027, 3, 17, 10))
    create(:event, space: space, title: "Team sync", event_type: "meeting",
                   start_time: Time.zone.local(2027, 3, 16, 13), end_time: Time.zone.local(2027, 3, 16, 14))
  end

  around { |ex| travel_to(Time.zone.local(2027, 3, 16, 12)) { ex.run } }

  def show_admin_calendar(query = "")
    log_in_as(admin, to: "#{admin_calendar_index_path}#{query}", local_storage: { fullCalendarDefaultDateAdmin: "2027-03-16T12:00:00.000Z" })
  end

  def event_count(title)
    page.all(".fc-timegrid-event", text: title, visible: :all).size
  end

  def expect_rendered_once(*titles)
    titles.each { |title| expect(page).to have_css(".fc-timegrid-event", text: title, count: 1, visible: :all) }
  end

  # N+1 pinned (the JSON feed reads event_assignments per event)
  it "shows events of every type", js: true, skip_bullet: true do
    show_admin_calendar

    expect_rendered_once("Soldering training", "Laser training", "Team sync")
    expect(page).to have_checked_field("checkbox-training", visible: :all)
    expect(page).to have_checked_field("checkbox-meeting", visible: :all)
  end

  it "hides only the unchecked type", js: true, skip_bullet: true do
    show_admin_calendar
    expect_rendered_once("Soldering training", "Team sync")

    uncheck "checkbox-training", allow_label_click: true

    expect(page).to have_no_css(".fc-timegrid-event", text: "training", visible: :all)
    expect_rendered_once("Team sync")
  end

  it "shows each event of a rechecked type exactly once", js: true, skip_bullet: true do
    show_admin_calendar
    expect_rendered_once("Soldering training")

    uncheck "checkbox-training", allow_label_click: true
    expect(page).to have_no_css(".fc-timegrid-event", text: "training", visible: :all)
    check "checkbox-training", allow_label_click: true

    expect_rendered_once("Soldering training", "Laser training", "Team sync")
    expect(event_count("training")).to eq(2)
  end

  it "starts with a type hidden when the URL lists it", js: true, skip_bullet: true do
    show_admin_calendar("?hidden_events=training")

    expect_rendered_once("Team sync")
    expect(page).to have_no_css(".fc-timegrid-event", text: "training", visible: :all)
    expect(page).to have_unchecked_field("checkbox-training", visible: :all)
    expect(page).to have_checked_field("checkbox-meeting", visible: :all)
  end
end
