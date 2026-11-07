# frozen_string_literal: true

require "rails_helper"

# Page script app/javascript/entrypoints/lockers.js: the range preview, the
# single-locker and bulk-edit modals, row selection and the product link box.
RSpec.describe "Locker inventory dialogs", type: :system, skip_bullet: true do
  include_context "with lockers on"

  let!(:l1) { create(:locker, specifier: "1", locker_size: size_small) }
  let!(:l2) { create(:locker, specifier: "2", locker_size: size_small) }
  let!(:l3) { create(:locker, specifier: "3", locker_size: size_small) }
  let!(:l7) { create(:locker, specifier: "7", locker_size: size_small) }

  before do
    log_in_as(admin, to: lockers_path)
    expect(page).to have_css("#locker_inventory_table")
    wait_for_app_js
  end

  def open_modal(button, selector)
    click_button button
    wait_for_modal_ready(selector)
  end

  describe "range preview" do
    before { open_modal "Make a range of lockers", "#newRangeLockerModal" }

    def type_range(from, to)
      fill_in "newLockerRangeStart", with: from
      fill_in "newLockerRangeEnd", with: to
    end

    it "lists the existing lockers to skip and the ones to create as collapsed ranges" do
      type_range("1", "9")
      within("#newRangeLockersAlreadyPresent") do
        expect(page).to have_css("li", text: "Range from 1 to 3")
        expect(page).to have_css("li", text: "7")
        expect(page).to have_css("li", count: 2)
      end
      within("#newRangeLockersPossible") do
        expect(page).to have_css("li", text: "Range from 4 to 6")
        expect(page).to have_css("li", text: "Range from 8 to 9")
        expect(page).to have_css("li", count: 2)
      end
    end

    it "hides the already-present list when the range has no existing locker" do
      type_range("20", "22")
      expect(page).to have_css("#newRangeLockersPossible li", text: "Range from 20 to 22")
      expect(page).to have_css("#newRangeLockersAlreadyPresent", visible: :hidden)
    end

    it "keeps the previous preview while the range is reversed" do
      type_range("20", "22")
      expect(page).to have_css("#newRangeLockersPossible li", text: "Range from 20 to 22")
      fill_in "newLockerRangeEnd", with: "10"
      expect(page).to have_field("newLockerRangeEnd", with: "10")
      expect(page).to have_css("#newRangeLockersPossible li", text: "Range from 20 to 22")
    end

    it "creates the missing lockers of the range with the chosen size and skips existing ones" do
      type_range("1", "9")
      within("#newRangeLockerModal") do
        select "24x24", from: "locker_size_id", visible: :all
        find("input[type=submit]").click
      end
      expect(page).to have_text("Lockers created")
      expect(Locker.pluck(:specifier)).to match_array(%w[1 2 3 4 5 6 7 8 9])
      expect(Locker.find_by(specifier: "5").locker_size).to eq(size_large)
      expect(Locker.find_by(specifier: "1").locker_size).to eq(size_small)
    end

    it "is refused by the server for a one-number range" do
      type_range("50", "50")
      expect(page).to have_css("#newRangeLockersPossible li", text: "50")
      within("#newRangeLockerModal") do
        select "24x24", from: "locker_size_id", visible: :all
        find("input[type=submit]").click
      end
      expect(page).to have_text("Range end must be larger than range start")
      expect(Locker.where(specifier: "50")).to be_empty
    end

    it "compares the range ends as text on the server, so 9 to 10 is refused" do
      type_range("9", "10")
      within("#newRangeLockerModal") do
        select "24x24", from: "locker_size_id", visible: :all
        find("input[type=submit]").click
      end
      expect(page).to have_text("Range end must be larger than range start")
      expect(Locker.where(specifier: %w[9 10])).to be_empty
    end
  end

  describe "single locker" do
    it "creates a locker with the chosen size and opens it" do
      open_modal "Make a single locker", "#newLockerModal"
      within("#newLockerModal") do
        fill_in "locker_specifier", with: "55"
        select "24x24", from: "locker_locker_size_id", visible: :all
        click_button "Create Locker"
      end
      expect(page).to have_text("Created locker #55")
      created = Locker.find_by(specifier: "55")
      expect(created.locker_size).to eq(size_large)
      expect(page).to have_current_path(locker_path(created))
    end

    it "shows variant details in the size dropdown of the modal" do
      open_modal "Make a single locker", "#newLockerModal"
      within("#newLockerModal") do
        expect(page).to have_css("select.tomselected", visible: :all)
        find(".ts-wrapper .ts-control").click
        expect(page).to have_css(".ts-dropdown .option", text: "SKU: SKU-S")
        expect(page).to have_css(".ts-dropdown .option", text: "Display Name: Large locker")
      end
    end
  end

  describe "row selection and bulk edit" do
    def select_rows(*lockers)
      lockers.each do |l|
        find("tr[data-locker-id='#{l.id}'] td:first-child").click(:control)
      end
    end

    it "lists the selected lockers in the bulk dialog with their ids as hidden fields" do
      select_rows(l1, l3)
      open_modal "Bulk edit", "#lockerBulkEditModal"
      within("#lockerBulkEditList") do
        expect(page).to have_css("li", count: 2)
        expect(page).to have_css("li", text: "#1")
        expect(page).to have_css("li", text: "#3")
        ids = all("input[name='id[]']", visible: :all).map(&:value)
        expect(ids).to match_array([l1.id.to_s, l3.id.to_s])
      end
    end

    it "keeps only the last row selected when rows are clicked without a modifier key" do
      find("tr[data-locker-id='#{l1.id}'] td:first-child").click
      find("tr[data-locker-id='#{l3.id}'] td:first-child").click
      open_modal "Bulk edit", "#lockerBulkEditModal"
      expect(page).to have_css("#lockerBulkEditList li", count: 1, text: "#3")
    end

    it "lists nothing when no row is selected" do
      open_modal "Bulk edit", "#lockerBulkEditModal"
      expect(page).to have_no_css("#lockerBulkEditList li")
    end

    it "is refused with a missing-parameter error, so no locker size changes" do
      select_rows(l1, l3)
      open_modal "Bulk edit", "#lockerBulkEditModal"
      within("#lockerBulkEditModal") do
        select "24x24", from: "locker_size_id", visible: :all
        click_button "Update Lockers"
      end
      expect(page).to have_text("param is missing or the value is empty or invalid: locker")
      expect([l1, l2, l3].map { |l| l.reload.locker_size }).to all(eq(size_small))
    end

    it "deletes the selected lockers after confirmation" do
      select_rows(l2)
      open_modal "Bulk edit", "#lockerBulkEditModal"
      accept_confirm { click_button "Delete Selected" }
      expect(page).to have_text("Selected lockers deleted")
      expect(Locker.exists?(l2.id)).to be(false)
      expect(Locker.exists?(l1.id)).to be(true)
    end
  end

  describe "locker product link" do
    before do
      find("[data-bs-target='#collapseLockerOptions']").click
      expect(page).to have_field("shopifyProductLink")
    end

    it "extracts the product id from a pasted link and saves it" do
      fill_in "shopifyProductLink", with: "https://admin.shopify.com/store/x/products/10478024917048"
      expect(page).to have_field("value", with: "10478024917048", readonly: true)
      find("form[action='/lockers/price'] input[type=submit]").click
      wait_until("link not saved") { LockerOption.locker_product_link == "gid://shopify/Product/10478024917048" }
    end

    it "leaves the id empty when the pasted text has no product id" do
      fill_in "shopifyProductLink", with: "https://admin.shopify.com/store/x/collections/9"
      expect(page).to have_field("value", with: "", readonly: true)
    end
  end

  describe "locker sizes" do
    before do
      wait_for_app_js
      find("[data-bs-target='#collapseLockerOptions']").click
      expect(page).to have_text("Create a new locker size")
    end

    it "creates a local size linked to the chosen variant" do
      fill_in "locker_size_size", with: "30x30"
      native = find("form", text: "Create a new locker size").find("#locker_size_shopify_gid", visible: :all)
      wrapper = native.find(:xpath, "following-sibling::div[contains(@class,'ts-wrapper')][1]")
      wrapper.find(".ts-control").click
      wrapper.find(".ts-control input").send_keys("New locker")
      expect(wrapper).to have_css(".ts-dropdown .option", count: 1)
      wrapper.find(".ts-control input").send_keys(:enter)
      expect(wrapper).to have_css(".ts-control .item", text: "New locker")
      click_button "Create Locker size"
      wait_until("size not created") { LockerSize.exists?(size: "30x30") }
      expect(LockerSize.find_by(size: "30x30").shopify_gid).to eq("gid-new")
    end

    it "creates a local size straight from an unlinked store variant" do
      click_button "Create local size"
      wait_until("size not created") { LockerSize.exists?(shopify_gid: "gid-new") }
      expect(LockerSize.find_by(shopify_gid: "gid-new").size).to eq("New variant")
    end

  end

  describe "locker sizes without a store variant" do
    let!(:unused) { create(:locker_size, size: "99x99", shopify_gid: "gid-missing") }

    def open_size_controls
      visit lockers_path
      wait_for_app_js
      find("[data-bs-target='#collapseLockerOptions']").click
      expect(page).to have_text("Create a new locker size")
    end

    it "deletes an unused local size after confirmation" do
      open_size_controls
      within(:xpath, "//tr[td[normalize-space()='99x99']]") do
        accept_confirm { find("button[aria-label='Delete']").click }
      end
      wait_until("size not deleted") { !LockerSize.exists?(unused.id) }
    end

    it "shows no options in the size dropdown of the single locker modal" do
      visit lockers_path
      wait_for_app_js
      open_modal "Make a single locker", "#newLockerModal"
      within("#newLockerModal") do
        find(".ts-wrapper .ts-control").click
        expect(page).to have_no_css(".ts-dropdown .option")
      end
    end
  end
end
