# frozen_string_literal: true

require "rails_helper"

# Page scripts app/javascript/entrypoints/locker_rentals.js (user request form),
# locker_rental_form.js (searchable pickers) and locker_admin.js (indefinite box,
# hover notes) on the locker rental pages. The payment journey is in
# spec/system/journeys/locker_journey_spec.rb; its Shopify stubs are reused here.
RSpec.describe "Locker rental forms", type: :system, skip_bullet: true do
  include_context "with lockers on"

  before do
    stub_shopify_admin!
    allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields).and_return(nil)
  end

  describe "request form for a user" do
    let(:user) { create(:user, :regular_user) }
    let!(:locker_a) { create(:locker, specifier: "A1", locker_size: size_small, audience: "general") }
    let!(:locker_b) { create(:locker, specifier: "B2", locker_size: size_large, audience: "general", available: false) }

    before do
      log_in_as(user)
      visit new_locker_rental_path
      expect(page).to have_select("locker_rental_requested_as")
      wait_for_app_js
    end

    it "keeps the course fieldset hidden and disabled for a general request" do
      expect(page).to have_css("#repo-select[hidden][disabled]", visible: :all)
    end

    it "lets the preferred locker be picked from a searchable list with its size" do
      native = find("#locker_rental_preferred_locker_id", visible: :all)
      wrapper = native.find(:xpath, "following-sibling::div[contains(@class,'ts-wrapper')][1]")
      wrapper.find(".ts-control").click
      expect(wrapper).to have_css(".ts-dropdown .option", text: "Locker A1 - Size 12x12", exact_text: true)
      expect(wrapper).to have_css(".ts-dropdown .option", text: "Locker B2 - Size 24x24 - Staff only", exact_text: true)
    end

    it "saves the picked preferred locker with the request" do
      native = find("#locker_rental_preferred_locker_id", visible: :all)
      wrapper = native.find(:xpath, "following-sibling::div[contains(@class,'ts-wrapper')][1]")
      wrapper.find(".ts-control").click
      wrapper.find(".ts-dropdown .option", text: "Locker A1 - Size 12x12", exact_text: true).click
      select "General request", from: "locker_rental_requested_as"
      click_button "Submit request"
      expect(page).to have_text("You have a pending request for a locker submitted on")
      expect(LockerRental.order(:id).last.preferred_locker).to eq(locker_a)
    end
  end

  describe "request form for a student" do
    let(:user) { create(:user, :student) }
    let!(:course) { CourseName.first || CourseName.create!(name: "GNG1103") }

    before do
      create(:locker, specifier: "S1", locker_size: size_small, audience: "gng")
      log_in_as(user)
      visit new_locker_rental_path
      expect(page).to have_select("locker_rental_requested_as")
      wait_for_app_js
    end

    it "keeps the course fieldset hidden and disabled while the blank choice is selected" do
      expect(page).to have_field("locker_rental_requested_as", with: "")
      expect(page).to have_css("#repo-select[hidden][disabled]", visible: :all)
    end

    it "hides and disables the course fieldset again for a general request, and back" do
      select "General request", from: "locker_rental_requested_as"
      expect(page).to have_css("#repo-select[hidden][disabled]", visible: :all)
      select "GNG student", from: "locker_rental_requested_as"
      expect(page).to have_css("#repo-select:not([hidden]):not([disabled])")
    end

    it "submits the course answers of a student request" do
      select "GNG student", from: "locker_rental_requested_as"
      fill_in "locker_rental_section_name", with: "C3"
      fill_in "locker_rental_team_name", with: "Team 9"
      click_button "Submit request"
      expect(page).to have_text("You have a pending request for a locker submitted on")
      rental = LockerRental.order(:id).last
      expect(rental).to have_attributes(requested_as: "student", section_name: "C3", team_name: "Team 9")
    end
  end

  describe "staff assign form" do
    let(:staff_user) { create(:user, :staff) }
    let!(:tenant) { create(:user, :regular_user, name: "Zelda Tenant", username: "zeldat") }
    let!(:locker) { create(:locker, specifier: "301", locker_size: size_small) }
    let!(:staff_only_locker) { create(:locker, specifier: "302", locker_size: size_large, available: false) }
    let!(:colleague) { create(:user, :staff, name: "Sasha Staffer") }

    before do
      log_in_as(staff_user)
      visit assign_locker_locker_rentals_path
      expect(page).to have_css("#locker_rental_rented_by_id.tomselected", visible: :all)
      wait_for_app_js
    end

    def pick(id, text, search: nil)
      native = find("##{id}", visible: :all)
      wrapper = native.find(:xpath, "following-sibling::div[contains(@class,'ts-wrapper')][1]")
      wrapper.find(".ts-control").click
      wrapper.find(".ts-control input").send_keys(search) if search
      wrapper.find(".ts-dropdown .option", text: text).click
      page.execute_script("arguments[0].tomselect.close()", native)
    end

    it "finds a user by name in the searchable user list and shows the picked locker with its size" do
      native = find("#locker_rental_rented_by_id", visible: :all)
      wrapper = native.find(:xpath, "following-sibling::div[contains(@class,'ts-wrapper')][1]")
      wrapper.find(".ts-control").click
      wrapper.find(".ts-control input").send_keys("Zelda")
      expect(wrapper).to have_css(".ts-dropdown .option", text: "Zelda Tenant (zeldat)")
      wrapper.find(".ts-dropdown .option", text: "Zelda Tenant (zeldat)").click
      expect(wrapper).to have_css(".ts-control .item", text: "Zelda Tenant (zeldat)")

      pick "locker_rental_locker_id", "Locker #301 (12x12) - Size 12x12"
      expect(page).to have_css("#locker_rental_locker_id + .ts-wrapper .item", text: "Locker #301 (12x12) - Size 12x12")
    end

    it "shows a staff badge next to staff users in the user list" do
      native = find("#locker_rental_rented_by_id", visible: :all)
      wrapper = native.find(:xpath, "following-sibling::div[contains(@class,'ts-wrapper')][1]")
      wrapper.find(".ts-control").click
      expect(wrapper).to have_css(".ts-dropdown .option .badge", text: "Staff")
    end

    it "marks a locker kept for staff in the list and shows the staff badge on a picked staff user" do
      pick "locker_rental_locker_id", "302"
      expect(page).to have_css("#locker_rental_locker_id + .ts-wrapper .item", text: "Staff only")
      pick "locker_rental_rented_by_id", "Sasha Staffer", search: "Sasha"
      expect(page).to have_css("#locker_rental_rented_by_id + .ts-wrapper .item .badge", text: "Staff")
    end

    it "assigns the locker immediately with the chosen end date" do
      pick "locker_rental_rented_by_id", "Zelda Tenant (zeldat)", search: "zelda"
      pick "locker_rental_locker_id", "#301"
      fill_in "assign_owned_until", with: Date.new(2031, 1, 15)
      fill_in "locker_rental_staff_notes", with: "Hand over keys"
      click_button "Assign Locker"

      wait_until("rental not created") { LockerRental.exists?(rented_by_id: tenant.id) }
      rental = LockerRental.find_by(rented_by_id: tenant.id)
      expect(rental).to have_attributes(state: "active", locker_id: locker.id, staff_notes: "Hand over keys")
      expect(rental.owned_until.to_date).to eq(Date.new(2031, 1, 15))
    end

    it "clears the end date while Indefinite is ticked and assigns without an end date" do
      pick "locker_rental_rented_by_id", "Zelda Tenant (zeldat)", search: "zelda"
      pick "locker_rental_locker_id", "#301"
      check "Indefinite (No expiry)"
      expect(page).to have_field("assign_owned_until", disabled: true, with: "")
      click_button "Assign Locker"

      wait_until("rental not created") { LockerRental.exists?(rented_by_id: tenant.id) }
      expect(LockerRental.find_by(rented_by_id: tenant.id).owned_until).to be_nil
    end

    it "leaves the end date empty when Indefinite is ticked and then cleared" do
      check "Indefinite (No expiry)"
      expect(page).to have_field("assign_owned_until", disabled: true)
      uncheck "Indefinite (No expiry)"
      expect(page).to have_field("assign_owned_until", disabled: false, with: "")
    end
  end

  describe "staff actions on a request" do
    let(:staff_user) { create(:user, :staff) }
    let!(:locker) { create(:locker, specifier: "401", locker_size: size_small) }
    let!(:rental) { create(:locker_rental, :general) }

    before do
      log_in_as(staff_user)
      visit locker_rental_path(rental)
      expect(page).to have_text("Staff Actions")
      wait_for_app_js
    end

    it "starts the checkout form with its end date enabled and the assign form indefinite" do
      expect(page).to have_field("owned_until_checkout", disabled: false)
      expect(page).to have_checked_field("indefinite_assign")
      expect(page).to have_field("owned_until_assign", disabled: true)
    end

    it "clears and disables the end date while Indefinite is ticked on the checkout form" do
      check "indefinite_checkout"
      expect(page).to have_field("owned_until_checkout", disabled: true, with: "")
      uncheck "indefinite_checkout"
      expect(page).to have_field("owned_until_checkout", disabled: false, with: "")
    end

    it "assigns the locker without an end date and activates the request" do
      within(:xpath, "//form[.//button[contains(normalize-space(.),'Assign Now')]]") do
        pick_in_form "locker_rental_locker_id", "401"
        accept_confirm { click_button "Assign Now" }
      end
      expect(page).to have_text("Locker rental updated")
      expect(rental.reload).to have_attributes(state: "active", locker_id: locker.id, owned_until: nil)
    end

    it "keeps the request unchanged when the assignment is not confirmed" do
      within(:xpath, "//form[.//button[contains(normalize-space(.),'Assign Now')]]") do
        pick_in_form "locker_rental_locker_id", "401"
        dismiss_confirm { click_button "Assign Now" }
      end
      expect(page).to have_text("Staff Actions")
      expect(rental.reload.state).to eq("reviewing")
    end

    it "cancels the request after confirmation" do
      accept_confirm { click_button "Cancel Request" }
      expect(page).to have_text("This locker request has been finished and cannot be re-enabled.")
      expect(rental.reload.state).to eq("cancelled")
    end

    def pick_in_form(id, text)
      native = find("select##{id}", visible: :all)
      wrapper = native.find(:xpath, "following-sibling::div[contains(@class,'ts-wrapper')][1]")
      wrapper.find(".ts-control").click
      wrapper.find(".ts-dropdown .option", text: text).click
      page.execute_script("arguments[0].tomselect.close()", native)
    end
  end

  describe "staff actions on an active rental" do
    let(:staff_user) { create(:user, :staff) }
    let!(:old_locker) { create(:locker, specifier: "501", locker_size: size_small) }
    let!(:rental) { create(:locker_rental, :active, locker: old_locker) }

    it "ends the rental after confirmation" do
      log_in_as(staff_user)
      visit locker_rental_path(rental)
      expect(page).to have_text("Staff Actions")
      accept_confirm { click_button "End Rental" }
      expect(page).to have_text("This locker request has been finished and cannot be re-enabled.")
      expect(rental.reload.state).to eq("cancelled")
    end

    it "keeps the end date enabled in the move form of a dated rental" do
      log_in_as(staff_user)
      visit locker_rental_path(rental)
      expect(page).to have_unchecked_field("indefinite_assign")
      expect(page).to have_field("owned_until_assign", disabled: false)
    end
  end
end
