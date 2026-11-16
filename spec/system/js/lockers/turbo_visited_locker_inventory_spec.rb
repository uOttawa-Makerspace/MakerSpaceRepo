# frozen_string_literal: true

require "rails_helper"

# The locker inventory reached by a Turbo visit from another admin page: Turbo
# adds the lockers page script on that visit and runs it after the visit's
# turbo:load, so its pickers, inline editing and range preview must not wait
# for one.
RSpec.describe "Locker inventory reached by a Turbo visit", type: :system, skip_bullet: true do
  include_context "with lockers on"

  let!(:locker) { create(:locker, specifier: "1", locker_size: size_small) }
  let(:row) { "tr[data-locker-id='#{locker.id}']" }

  before do
    log_in_as(admin, to: admin_users_path)
    wait_for_app_js
    page.execute_script("window.turboDocument = true; Turbo.visit(arguments[0])", lockers_path)
    expect(page).to have_current_path(lockers_path)
    expect(page).to have_css("#locker_inventory_table")
  end

  after { expect(page.evaluate_script("window.turboDocument")).to be(true) }

  it "sets up each size picker once" do
    expect(page).to have_css("#{row} select.locker-variant-select.tomselected", visible: :all)
    expect(page).to have_css("#{row} .ts-wrapper", count: 1)
  end

  it "turns inline editing on and off with the switch" do
    expect(page).to have_css("#{row} select[name='locker[audience]'][disabled]")
    check "Inline editing"
    expect(page).to have_no_css("#{row} select[name='locker[audience]'][disabled]")
    expect(page).to have_no_css("#{row} .ts-wrapper.disabled")
    uncheck "Inline editing"
    expect(page).to have_css("#{row} select[name='locker[audience]'][disabled]")
  end

  it "saves an inline edit on change" do
    check "Inline editing"
    within(row) { select "Staff", from: "locker[audience]" }
    expect(page).to have_css("#{row} select[name='locker[audience]'].is-valid")
    expect(locker.reload.audience).to eq("staff")
  end

  it "previews the range of lockers to create" do
    click_button "Make a range of lockers"
    wait_for_modal_ready("#newRangeLockerModal")
    fill_in "newLockerRangeStart", with: "1"
    fill_in "newLockerRangeEnd", with: "3"
    expect(page).to have_css("#newRangeLockersAlreadyPresent li", text: "1")
    expect(page).to have_css("#newRangeLockersPossible li", text: "Range from 2 to 3")
  end

  it "fills the product id from a pasted product link" do
    find("[data-bs-target='#collapseLockerOptions']").click
    fill_in "shopifyProductLink", with: "https://admin.shopify.com/store/x/products/42"
    expect(page).to have_field("value", with: "42", readonly: true)
  end
end
