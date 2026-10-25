# frozen_string_literal: true

require "rails_helper"

# End-to-end spaces journey: an admin edits a space's contact info (including
# its opening-hours block) and the public contact page shows the new details.
# The opening hours themselves are no longer rendered publicly (D-E2E07).
RSpec.describe "Journey: space contact info and hours", type: :system do
  let!(:admin) { create(:user, :admin) }
  let!(:space) { create(:space, name: "Hours Space") }
  let!(:info) do
    create(:contact_info, name: "Hours Space", space_id: space.id, email: "old@example.com",
                          address: "1 Old Road", phone_number: "613-000-0000", show_hours: true)
  end

  before do
    info.opening_hours.create!(target_en: "Old header", target_fr: "Ancien", closed_all_week: :open)
  end

  it "admin edits address, phone and the opening-hours block -> public contact page updates" do
    visit contact_path
    expect(page).to have_text("1 Old Road")

    as_actor(:admin) do
      log_in_as(admin)
      visit edit_admin_contact_info_path(info)
      expect(page).to have_css("h2", text: "Edit Contact Info")
      fill_in "contact_info_address", with: "99 New Street"
      fill_in "contact_info_phone_number", with: "613-555-0123"
      fill_in "contact_info_email", with: "hours@example.com"
      fill_in "contact_info_opening_hours_attributes_0_target_en", with: "Weekday hours"
      fill_in "contact_info_opening_hours_attributes_0_monday_opening", with: "09:00AM"
      fill_in "contact_info_opening_hours_attributes_0_monday_closing", with: "05:30PM"
      click_button "Edit Contact Info"
      expect(page).to have_text("Contact Info updated")
    end

    info.reload
    expect(info.address).to eq("99 New Street")
    expect(info.phone_number).to eq("613-555-0123")
    hour = info.opening_hours.first
    expect(hour.target_en).to eq("Weekday hours")
    expect(hour.monday_opening.strftime("%H:%M")).to eq("09:00")
    expect(hour.monday_closing.strftime("%H:%M")).to eq("17:30")

    visit contact_path
    expect(page).to have_text("99 New Street")
    expect(page).to have_text("613-555-0123")
    expect(page).to have_text("hours@example.com")
    expect(page).to have_no_text("1 Old Road")
    # WART(D-E2E07): the saved opening hours / table header are not shown on
    # any public page (the hours page is calendar-driven; the form is deprecated).
    expect(page).to have_no_text("Weekday hours")
    visit hours_path
    expect(page).to have_css("#calendar")
    expect(page).to have_no_text("Weekday hours")
  end
end
