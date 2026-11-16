# frozen_string_literal: true

require "rails_helper"

# The "Imported Calendars // Staff Needed Calendar" rows on the space edit page
# (entrypoints/space_staff_needed_calendar.js).

RSpec.describe "Space settings: staff needed calendars", type: :system do
  let!(:space) { create(:space, name: "Calendar Lab") }
  let!(:admin) { create(:user, :admin, space_id: space.id) }

  def open_settings
    log_in_as(admin, to: edit_admin_space_path(space))
    expect(page).to have_css("#new-snc")
  end

  def rows
    page.all("#link-container .upload-file-input")
  end

  it "lists the calendars the space already has", js: true, skip_bullet: true do
    StaffNeededCalendar.create!(calendar_url: "https://feeds.example.org/a.ics", name: "A", space_id: space.id)
    open_settings

    expect(rows.size).to eq(1)
    expect(page).to have_field(with: "https://feeds.example.org/a.ics")
  end

  it "adds a blank row each time New Calendar is pressed", js: true, skip_bullet: true do
    open_settings
    click_button "New Calendar"
    click_button "New Calendar"

    expect(rows.size).to eq(2)
    expect(rows.last.all("input[type=text]").map(&:value)).to eq(["", ""])
    expect(rows.last["id"]).to eq("")
  end

  it "removes a row with its delete button", js: true, skip_bullet: true do
    StaffNeededCalendar.create!(calendar_url: "https://feeds.example.org/a.ics", name: "A", space_id: space.id)
    open_settings
    find("#link-container .snc-delete-button").click

    expect(page).to have_css("#link-container .upload-file-input", count: 0)
  end

  it "saves the rows that are on the page", js: true, skip_bullet: true do
    StaffNeededCalendar.create!(calendar_url: "https://feeds.example.org/a.ics", name: "A", space_id: space.id)
    open_settings
    click_button "New Calendar"
    new_row = rows.last
    new_row.all("input[type=text]")[0].set("Timetable")
    new_row.all("input[type=text]")[1].set("https://feeds.example.org/b.ics")
    click_button "Save Calendars"

    expect_flash("Calendars updated successfully.")
    expect(StaffNeededCalendar.where(space_id: space.id).pluck(:name, :calendar_url))
      .to contain_exactly(["A", "https://feeds.example.org/a.ics"], ["Timetable", "https://feeds.example.org/b.ics"])
    # a new row's colour input starts empty, which the browser submits as black
    expect(StaffNeededCalendar.find_by!(name: "Timetable").color).to eq("#000000")
  end

  it "keeps a removed row out of what is saved", js: true, skip_bullet: true do
    StaffNeededCalendar.create!(calendar_url: "https://feeds.example.org/a.ics", name: "A", space_id: space.id)
    open_settings
    find("#link-container .snc-delete-button").click
    click_button "Save Calendars"

    expect_flash("Calendars updated successfully.")
    expect(StaffNeededCalendar.where(space_id: space.id)).to be_empty
  end
end
