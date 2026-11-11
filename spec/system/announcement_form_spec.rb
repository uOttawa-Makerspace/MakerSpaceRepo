# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Announcement forms", type: :system do
  let(:admin) { create(:user, :admin) }
  let(:announcement) { create(:announcement, end_date: 3.days.from_now.to_date) }

  def end_date_value
    page.evaluate_script("document.querySelector('#end_date').value")
  end

  def clear_end_date
    expect(page).to have_css("#end_date.flatpickr-input", visible: :all)
    click_button "Clear End Date"
    expect(end_date_value).to eq("")
  end

  it "sets the end date with the calendar and clears it on the admin new form" do
    log_in_as(admin, to: new_admin_announcement_path)
    expect(page).to have_css("#end_date.flatpickr-input", visible: :all)
    page.execute_script("document.querySelector('#end_date')._flatpickr.setDate(new Date(Date.now() + 86400000 * 3), true)")
    expect(end_date_value).to match(/\A\d{4}-\d{2}-\d{2}\z/)

    clear_end_date
  end

  it "clears the end date on the admin edit form" do
    log_in_as(admin, to: edit_admin_announcement_path(announcement))
    expect(page).to have_css("#end_date.flatpickr-input", visible: :all)
    expect(end_date_value).to eq(announcement.end_date.to_s)

    clear_end_date
  end

  it "sets the end date with the calendar and clears it on the staff new form" do
    log_in_as(admin, to: new_announcement_path)
    expect(page).to have_css("#end_date.flatpickr-input", visible: :all)
    page.execute_script("document.querySelector('#end_date')._flatpickr.setDate(new Date(Date.now() + 86400000 * 3), true)")
    expect(end_date_value).to match(/\A\d{4}-\d{2}-\d{2}\z/)

    clear_end_date
  end

  it "clears the end date on the staff edit form" do
    log_in_as(admin, to: edit_announcement_path(announcement))
    expect(page).to have_css("#end_date.flatpickr-input", visible: :all)
    expect(end_date_value).to eq(announcement.end_date.to_s)

    clear_end_date
  end

  it "keeps a past end date when the staff edit form is saved without touching it" do
    past = create(:announcement, end_date: 10.days.ago.to_date)
    log_in_as(admin, to: edit_announcement_path(past))
    expect(page).to have_css("#end_date.flatpickr-input", visible: :all)
    expect(end_date_value).to eq(past.end_date.to_s)
    click_button "Update Announcement"

    expect(page).to have_no_current_path(edit_announcement_path(past))
    expect(past.reload.end_date).to eq(10.days.ago.to_date)
  end

  it "saves an announcement with its end date cleared on the staff edit form" do
    log_in_as(admin, to: edit_announcement_path(announcement))
    clear_end_date
    click_button "Update Announcement"

    expect(page).to have_no_current_path(edit_announcement_path(announcement))
    expect(announcement.reload.end_date).to be_nil
  end

  {
    "admin new form" => -> { new_admin_announcement_path },
    "admin edit form" => -> { edit_admin_announcement_path(announcement) },
    "staff new form" => -> { new_announcement_path },
    "staff edit form" => -> { edit_announcement_path(announcement) }
  }.each do |name, path|
    it "labels the end date field on the #{name}" do
      log_in_as(admin, to: instance_exec(&path))
      expect(page).to have_css("#end_date.flatpickr-input", visible: :all)
      expect(find("label", text: "End Date (Optional)")[:for]).to eq("end_date_display")
      expect(find_field("End Date (Optional)")[:id]).to eq("end_date_display")
    end
  end
end
