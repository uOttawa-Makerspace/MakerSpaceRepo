# frozen_string_literal: true

require "rails_helper"

# Page script app/javascript/entrypoints/keys.js on the admin key pages (new,
# edit, assign, revoke, show). Real login, real page JS.
RSpec.describe "Admin key pages", type: :system, skip_bullet: true do
  let(:admin) { create(:user, :admin) }
  let!(:space) { create(:space, name: "Machine Shop", keycode: "MS-1") }
  let!(:other_space) { create(:space, name: "Wood Shop", keycode: "WS-2") }

  def style_of(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).parentElement.style.display")
  end

  describe "new key form" do
    before do
      log_in_as(admin)
      visit new_admin_key_path
      expect(page).to have_css("#space-select.tomselected", visible: :all)
    end

    it "shows the space and hides the keycode for a regular key" do
      expect(page).to have_select("key-type-select", selected: "Regular")
      expect(page).to have_css("#space-select + .ts-wrapper")
      expect(page).to have_no_field("custom-keycode", visible: :visible)
    end

    it "swaps the space for the keycode when another key type is chosen, and back" do
      select "Keycard", from: "key-type-select"
      expect(page).to have_field("custom-keycode", visible: :visible)
      expect(page).to have_no_css("#space-select + .ts-wrapper", visible: :visible)
      select "Regular", from: "key-type-select"
      expect(page).to have_no_field("custom-keycode", visible: :visible)
      expect(page).to have_css("#space-select + .ts-wrapper", visible: :visible)
    end

    it "hides the notes box for an inventory key and shows it again for another status" do
      expect(page).to have_css("#notes-container", visible: :visible)
      select "Inventory", from: "status-select"
      expect(page).to have_no_css("#notes-container", visible: :visible)
      select "Lost", from: "status-select"
      expect(page).to have_css("#notes-container", visible: :visible)
    end

    it "creates a regular key in the chosen space" do
      fill_in "key_number", with: "12"
      tom_select "Wood Shop (WS-2)", from: "space-select", search: "Wood"
      select "Inventory", from: "status-select"
      click_button "Create Key"
      expect(page).to have_text("Successfully created key.")
      expect(Key.find_by(number: 12)).to have_attributes(space_id: other_space.id, key_type: "regular", status: "inventory")
    end

    it "creates a keycard key with its own keycode" do
      select "Keycard", from: "key-type-select"
      fill_in "key_number", with: "77"
      fill_in "custom-keycode", with: "CARD-77"
      select "Inventory", from: "status-select"
      click_button "Create Key"
      expect(page).to have_text("Successfully created key.")
      expect(Key.find_by(number: 77)).to have_attributes(key_type: "keycard", custom_keycode: "CARD-77")
    end

    it "searches the supervisor list by name" do
      create(:user, :admin, name: "Quentin Boss")
      visit new_admin_key_path
      expect(page).to have_css("#supervisor-select.tomselected", visible: :all)
      tom_select "Quentin Boss", from: "supervisor-select", search: "Quen"
      expect(page).to have_css("#supervisor-select + .ts-wrapper .item", text: "Quentin Boss")
    end
  end

  describe "edit key form" do
    let!(:regular) { create(:key, :regular_key_type, :unknown_status, number: 5, space: space) }
    let!(:card) { create(:key, :keycard_key_type, :inventory_status, number: 6, custom_keycode: "C-6") }

    before { log_in_as(admin) }

    it "opens a regular key with the space shown, the keycode hidden and the notes shown" do
      visit edit_admin_key_path(regular)
      expect(page).to have_css("#space-select.tomselected", visible: :all)
      expect(page).to have_css("#space-select + .ts-wrapper", visible: :visible)
      expect(page).to have_no_field("custom-keycode", visible: :visible)
      expect(page).to have_css("#notes-container", visible: :visible)
    end

    it "opens an inventory keycard with the keycode shown and the notes hidden" do
      visit edit_admin_key_path(card)
      expect(page).to have_field("custom-keycode", visible: :visible, with: "C-6")
      expect(page).to have_no_css("#notes-container", visible: :visible)
    end

    it "changes the status and keeps the other values when updated" do
      visit edit_admin_key_path(regular)
      expect(page).to have_css("#space-select.tomselected", visible: :all)
      select "Lost", from: "status-select"
      click_button "Update Key"
      expect(page).to have_text("The key was successfully updated.")
      expect(regular.reload).to have_attributes(status: "lost", space_id: space.id, number: "5")
    end
  end

  describe "assign key form" do
    let!(:key) { create(:key, :regular_key_type, :inventory_status, number: 9, space: space) }
    let!(:holder) do
      create(:user, :staff, name: "Hank Holder").tap { |u| create(:key_request, :status_approved, :all_questions_answered, user: u, space: space, supervisor: admin) }
    end

    before do
      log_in_as(admin)
      visit admin_key_assign_path(key_id: key.id)
      expect(page).to have_css("#key-request-select.tomselected", visible: :all)
    end

    it "assigns the key to the user picked from the searchable list with the deposit" do
      tom_select "Hank Holder", from: "key-request-select", search: "Hank"
      fill_in "deposit_amount", with: "25"
      click_button "Assign Key"
      expect(page).to have_text("Successfully assigned key")
      expect(key.reload).to have_attributes(status: "held", user_id: holder.id, supervisor_id: admin.id)
      expect(KeyTransaction.find_by(key_id: key.id).deposit_amount).to eq(25)
    end

    it "preselects the signed-in admin as supervisor in a searchable list" do
      expect(page).to have_css("#supervisor-select + .ts-wrapper .item", text: admin.name)
    end
  end

  describe "revoke key form" do
    let!(:holder) { create(:user, :staff).tap { |u| create(:key_request, :status_approved, :all_questions_answered, user: u, space: space, supervisor: admin) } }
    let!(:key) { create(:key, :regular_key_type, :held_status, number: 3, space: space, user: holder, supervisor: admin) }
    let!(:deposit) { create(:key_transaction, key: key, user: holder, deposit_amount: 0) }

    include_context "with the browser in Toronto time"

    before { log_in_as(admin) }

    it "prefills today as the deposit return date when there is no deposit and clears it with the button" do
      visit admin_key_revoke_path(key_id: key.id)
      expect(page).to have_field("deposit-return-date", with: Time.zone.today.to_s)
      click_button "deposit-return-date-clear"
      expect(page).to have_field("deposit-return-date", with: "")
    end

    it "revokes the key and records the picked deposit return date" do
      deposit.update!(deposit_amount: 40)
      visit admin_key_revoke_path(key_id: key.id)
      expect(page).to have_field("deposit-return-date", with: "")
      find("#deposit-return-date").click
      find(".flatpickr-calendar.open .flatpickr-day.today").click
      expect(page).to have_field("deposit-return-date", with: Time.zone.today.to_s)
      click_button "Revoke Key"
      expect(page).to have_text("Successfully revoked key")
      expect(key.reload).to have_attributes(status: "inventory", user_id: nil)
      expect(deposit.reload.deposit_return_date).to eq(Time.zone.today)
      expect(deposit.return_date).to eq(Time.zone.today)
    end

    it "revokes the key with no deposit return date after the date is cleared" do
      deposit.update!(deposit_amount: 40)
      visit admin_key_revoke_path(key_id: key.id)
      find("#deposit-return-date").click
      find(".flatpickr-calendar.open .flatpickr-day.today").click
      click_button "deposit-return-date-clear"
      expect(page).to have_field("deposit-return-date", with: "")
      click_button "Revoke Key"
      expect(page).to have_text("Successfully revoked key")
      expect(key.reload.status).to eq("inventory")
      expect(deposit.reload.deposit_return_date).to be_nil
    end
  end

  describe "printing a key page" do
    let!(:holder) { create(:user, :staff).tap { |u| create(:key_request, :status_approved, :all_questions_answered, user: u, space: space, supervisor: admin) } }
    let!(:key) { create(:key, :regular_key_type, :held_status, number: 4, space: space, user: holder, supervisor: admin) }

    before do
      log_in_as(admin)
    end

    def count_prints
      page.execute_script("window.__prints = 0; window.print = function () { window.__prints += 1; };")
    end

    def prints
      page.evaluate_script("window.__prints")
    end

    it "prints the page straight away when there are no certificate frames" do
      visit admin_key_path(key)
      expect(page).to have_button("print-button")
      wait_for_app_js
      count_prints
      click_button "print-button"
      wait_until("print not called") { prints == 1 }
    end

    it "reloads the certificate frames and prints once they have all loaded" do
      cert = KeyCertification.create!(user: holder)
      cert.pdf_file_1.attach(io: StringIO.new("%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF"), filename: "w.pdf", content_type: "application/pdf")
      visit admin_key_path(key)
      expect(page).to have_css("iframe.key-cert-iframe", visible: :all, count: 1)
      wait_for_app_js
      count_prints
      click_button "print-button"
      expect(prints).to eq(0)
      wait_until("print not called after frames loaded") { prints == 1 }
    end
  end

  describe "moving between key pages with link clicks (a full page load)" do
    it "sets up the new key form's widgets when it is reached by a link from the key list" do
      log_in_as(admin)
      visit admin_keys_path
      wait_for_app_js
      click_link "Add a new Key"
      expect(page).to have_current_path(new_admin_key_path)
      expect(page).to have_css("#space-select.tomselected", visible: :all)
      select "Keycard", from: "key-type-select"
      expect(page).to have_field("custom-keycode", visible: :visible)
    end
  end
end
