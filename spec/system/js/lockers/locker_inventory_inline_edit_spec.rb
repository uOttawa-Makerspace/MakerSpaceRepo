# frozen_string_literal: true

require "rails_helper"

# Page script app/javascript/entrypoints/lockers.js (+ locker_admin.js) on the
# staff locker inventory: the inline-editing switch, the size/type/note fields
# that save on change, and the searchable table. Real login, real page JS.
RSpec.describe "Locker inventory inline editing", type: :system, skip_bullet: true do
  include_context "with lockers on"

  let!(:locker) { create(:locker, specifier: "101", locker_size: size_small, audience: "general") }
  let!(:other) { create(:locker, specifier: "102", locker_size: size_small, audience: "general") }
  let(:row) { "tr[data-locker-id='#{locker.id}']" }

  before do
    log_in_as(admin)
    visit lockers_path
    expect(page).to have_css("#locker_inventory_table")
    expect(page).to have_css("#{row} select.locker-variant-select.tomselected", visible: :all)
  end

  def switch_on
    wait_for_app_js
    check "Inline editing"
    expect(page).to have_field("locker[audience]", disabled: false, count: 2)
  end

  def pick_size(text)
    native = find(:select, "locker[locker_size_id]", visible: :all)
    wrapper = native.find(:xpath, "following-sibling::div[contains(@class, 'ts-wrapper')][1]")
    wrapper.find(".ts-control").click
    wrapper.find(".ts-dropdown .option", text: text).click
  end

  def commit_note(selector, value)
    field = find(selector)
    field.fill_in(with: value) rescue field.set(value)
    field.send_keys(:tab)
  end

  it "keeps the inline fields disabled until the switch is on, and disables them again when it is off" do
    expect(page).to have_css("#{row} select[name='locker[audience]'][disabled]")
    expect(page).to have_css("#{row} input[name='locker[notes]'][disabled]")

    check "Inline editing"
    expect(page).to have_no_css("#{row} select[name='locker[audience]'][disabled]")
    expect(page).to have_no_css("#{row} input[name='locker[notes]'][disabled]")
    expect(page).to have_no_css("#{row} .ts-wrapper.disabled")

    uncheck "Inline editing"
    expect(page).to have_css("#{row} select[name='locker[audience]'][disabled]")
    expect(page).to have_css("#{row} input[name='locker[notes]'][disabled]")
    expect(page).to have_css("#{row} .ts-wrapper.disabled")
  end

  it "saves a new locker type on change and flags the field as saved" do
    switch_on
    within(row) { select "Staff", from: "locker[audience]" }

    expect(page).to have_css("#{row} select[name='locker[audience]'].is-valid")
    expect(locker.reload.audience).to eq("staff")
    expect(other.reload.audience).to eq("general")
    # the saved flag fades by itself
    expect(page).to have_no_css("#{row} select[name='locker[audience]'].is-valid")
  end

  it "saves a locker note on change and refreshes the row's search text but not the hover note" do
    switch_on
    commit_note("#{row} input[name='locker[notes]']", "Door sticks")

    expect(page).to have_css("#{row} input[name='locker[notes]'].is-valid")
    expect(locker.reload.notes).to eq("Door sticks")
    expect(page).to have_css("#{row} td[data-search='Door sticks']")
    # the hover text is not refreshed: it keeps the text from before the save
    expect(page).to have_css("#{row} [data-bs-original-title='Locker Note (click inline editing to edit)']")
    expect(page).to have_no_css("#{row} [data-bs-original-title='Door sticks']")
  end

  it "keeps the old hover note after the note is cleared" do
    locker.update!(notes: "Old note")
    visit lockers_path
    expect(page).to have_css("#{row} input[name='locker[notes]']")
    switch_on
    commit_note("#{row} input[name='locker[notes]']", "")

    wait_until("note not cleared") { locker.reload.notes.blank? }
    expect(page).to have_css("#{row} [data-bs-original-title='Old note']")
    expect(page).to have_no_css("#{row} [data-bs-original-title='No note']")
  end

  it "saves a staff note of an assigned locker on its rental" do
    rental = create(:locker_rental, :active, locker: other, requested_as: "general")
    visit lockers_path
    expect(page).to have_css("tr[data-locker-id='#{other.id}'] input[name='locker_rental[staff_notes]']")
    switch_on
    commit_note("tr[data-locker-id='#{other.id}'] input[name='locker_rental[staff_notes]']", "Called twice")

    expect(page).to have_css("tr[data-locker-id='#{other.id}'] input[name='locker_rental[staff_notes]'].is-valid")
    expect(rental.reload.staff_notes).to eq("Called twice")
    expect(other.reload.notes).to be_blank
  end

  it "saves a new locker size chosen in the size dropdown" do
    switch_on
    within(row) { pick_size "24x24" }

    wait_until("size not saved") { locker.reload.locker_size == size_large }
    expect(other.reload.locker_size).to eq(size_small)
    # the spinner is gone and the check mark appears then fades
    expect(page).to have_no_css("#{row} .spinner-border:not([hidden])", visible: :all)
    expect(page).to have_no_css("#{row} select.is-invalid", visible: :all)
  end

  it "marks the size dropdown invalid when the save is refused and keeps the old size" do
    allow_any_instance_of(Locker).to receive(:update).and_return(false)
    switch_on
    within(row) { pick_size "24x24" }

    expect(page).to have_css("#{row} select.is-invalid", visible: :all)
    expect(locker.reload.locker_size).to eq(size_small)
    # the dropdown is usable again because the edit switch is still on
    expect(page).to have_no_css("#{row} .ts-wrapper.disabled")
    expect(page).to have_no_css("#{row} select.is-invalid", visible: :all)
  end

  it "marks a note invalid when the save is refused" do
    allow_any_instance_of(Locker).to receive(:update).and_return(false)
    switch_on
    commit_note("#{row} input[name='locker[notes]']", "Never saved")

    expect(page).to have_css("#{row} input[name='locker[notes]'].is-invalid")
    expect(locker.reload.notes).to be_blank
  end

  it "shows variant details when opening the size dropdown" do
    switch_on
    within(row) do
      wrapper = find(".ts-wrapper")
      wrapper.find(".ts-control").click
      expect(wrapper).to have_css(".ts-dropdown .option", text: "Display Name: Large locker")
      expect(wrapper).to have_css(".ts-dropdown .option", text: "SKU: SKU-L")
      expect(wrapper).to have_css(".ts-dropdown .option", text: "Price: 20.00")
    end
  end

  it "searches the table by status text, tenant and note" do
    create(:locker_rental, :active, locker: other, requested_as: "general")
    visit lockers_path
    expect(page).to have_css(".dt-search input")
    expect(find(".dt-search input")[:placeholder]).to eq("Search lockers, users, notes, status...")

    find(".dt-search input").set("free")
    expect(page).to have_css("tbody tr", count: 1)
    expect(page).to have_css("tr[data-locker-id='#{locker.id}']")

    find(".dt-search input").set("valid")
    expect(page).to have_css("tbody tr", count: 1)
    expect(page).to have_css("tr[data-locker-id='#{other.id}']")
  end

  it "sets up hover notes on the inventory (tooltip text shown on hover)" do
    locker.update!(notes: "Near the stairs")
    visit lockers_path
    expect(page).to have_css("#{row} [data-bs-original-title='Near the stairs']")
    wait_until("hover note not shown") do
      find("#{row} [data-bs-toggle='tooltip']").hover
      page.has_css?(".tooltip", text: "Near the stairs", wait: 1)
    end
  end
end
