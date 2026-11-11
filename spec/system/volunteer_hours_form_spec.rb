# frozen_string_literal: true

require "rails_helper"

# The hours form (volunteer_hours.js): the hours and minutes boxes are combined into the hidden
# total_time field when the form is submitted. Real login, real page JS.
RSpec.describe "Volunteer hours form", type: :system, skip_bullet: true do
  let(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let!(:task) { create(:volunteer_task, title: "stocktake", user_id: create(:user, :staff).id) }

  before do
    create(:volunteer_task_join, volunteer_task: task, user: volunteer, state: "joined", user_type: "Volunteer")
  end

  it "saves the hours and minutes entered as decimal hours" do
    log_in_as(volunteer, to: new_volunteer_hour_path)
    select "stocktake", from: "volunteer_hour_volunteer_task_id"
    fill_in "volunteer_hour_date_of_task", with: Date.current.strftime("%m%d%Y")
    fill_in "hours", with: "2"
    fill_in "minutes", with: "30"
    click_button "send"

    expect(page).to have_text("You've successfully sent your volunteer working hours")
    expect(VolunteerHour.where(user: volunteer).pluck(:total_time)).to eq([2.5])
  end

  it "updates the total when the hours of an existing entry are edited" do
    hour = create(:volunteer_hour, user: volunteer, volunteer_task: task, total_time: 1.0, date_of_task: Date.current)
    log_in_as(volunteer, to: edit_volunteer_hour_path(hour))
    fill_in "hours", with: "3"
    fill_in "minutes", with: "15"
    click_button "Update Volunteer Hour"

    expect(page).to have_text("Volunteer hour updated")
    expect(hour.reload.total_time).to eq(3.25)
  end

  it "keeps the stored total when an edit changes nothing" do
    hour = create(:volunteer_hour, user: volunteer, volunteer_task: task, total_time: 0.33, date_of_task: Date.current)
    log_in_as(volunteer, to: edit_volunteer_hour_path(hour))
    click_button "Update Volunteer Hour"

    expect(page).to have_text("Volunteer hour updated")
    expect(hour.reload.total_time).to eq(0.33)
  end
end
