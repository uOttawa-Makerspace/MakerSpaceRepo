# frozen_string_literal: true

require "rails_helper"

# Stimulus controller app/javascript/controllers/volunteer_search_controller.js
# on the volunteer directory. Real login, real page JS.
RSpec.describe "Volunteer directory search", type: :system, skip_bullet: true do
  let(:staff) { create(:user, :staff) }
  let(:search_box) { find("[data-volunteer-search-target='input']") }

  before do
    create(:user, :volunteer_with_volunteer_program, name: "Ann Archer")
    create(:user, :volunteer_with_volunteer_program, name: "Bob Baker")
    create(:user, :unactive_volunteer_with_volunteer_program, name: "Cy Carver")
    log_in_as(staff, to: volunteer_list_volunteers_path)
    expect(page).to have_css("tr[data-volunteer-search-target='activeRow']", count: 2)
    wait_for_app_js
  end

  def count_badge(which)
    find("[data-volunteer-search-target='#{which}Count']")
  end

  def clear_button
    find("[data-volunteer-search-target='clearButton']", visible: :all)
  end

  it "hides the active rows that do not match and counts the matches in each tab" do
    search_box.fill_in(with: "ann")
    expect(page).to have_css("tr[data-volunteer-search-target='activeRow']", text: "Ann Archer", count: 1)
    expect(page).to have_no_css("tr[data-volunteer-search-target='activeRow']", text: "Bob Baker")
    expect(count_badge("active")).to have_text("1")
    expect(count_badge("inactive")).to have_text("0")
    expect(clear_button).to be_visible
  end

  it "shows the no-match message in place of the active table" do
    search_box.fill_in(with: "zzz")
    expect(page).to have_css("[data-volunteer-search-target='activeEmpty']", visible: :visible)
    expect(page).to have_no_css("[data-volunteer-search-target='activeTableContainer']", visible: :visible)
    expect(count_badge("active")).to have_text("0")
  end

  it "counts the inactive matches and shows them on the inactive tab" do
    search_box.fill_in(with: "CARVER")
    expect(count_badge("inactive")).to have_text("1")
    expect(count_badge("active")).to have_text("0")
    click_button "inactive-tab"
    expect(page).to have_css("tr[data-volunteer-search-target='inactiveRow']", text: "Cy Carver", visible: :visible)
  end

  it "restores every row and the full counts when the clear button is clicked" do
    search_box.fill_in(with: "zzz")
    expect(count_badge("active")).to have_text("0")
    clear_button.click
    expect(search_box.value).to eq("")
    expect(page).to have_css("tr[data-volunteer-search-target='activeRow']", count: 2, visible: :visible)
    expect(count_badge("active")).to have_text("2")
    expect(count_badge("inactive")).to have_text("1")
    expect(page).to have_css("[data-volunteer-search-target='clearButton']", visible: :hidden)
    expect(page).to have_css("[data-volunteer-search-target='activeEmpty']", visible: :hidden)
  end

  it "counts the rows the list has now when the search is cleared" do
    page.execute_script(<<~JS)
      document.querySelector("tr[data-volunteer-search-target='activeRow']").remove();
    JS
    expect(page).to have_css("tr[data-volunteer-search-target='activeRow']", count: 1)
    search_box.fill_in(with: "zzz")
    expect(count_badge("active")).to have_text("0")
    clear_button.click
    expect(page).to have_css("tr[data-volunteer-search-target='activeRow']", count: 1, visible: :visible)
    expect(count_badge("active")).to have_text("1")
    expect(count_badge("inactive")).to have_text("1")
  end

  it "resets the search from the button in the no-match message" do
    search_box.fill_in(with: "zzz")
    within("[data-volunteer-search-target='activeEmpty']") { find("button").click }
    expect(page).to have_css("tr[data-volunteer-search-target='activeRow']", count: 2, visible: :visible)
    expect(count_badge("active")).to have_text("2")
  end
end
