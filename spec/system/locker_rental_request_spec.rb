# frozen_string_literal: true

require "rails_helper"

# Look-and-feel/flow characterization: a signed-in regular user requests a
# locker and sees the request pending. Real login (see
# spec/support/auth_helpers.rb); Shopify product lookup stubbed (no network).
RSpec.describe "Locker rental request", type: :system do
  let(:user) { create(:user, :regular_user) }

  before do
    LockerOption.where(name: [LockerOption::LOCKER_PRODUCT_LINK, LockerOption::LOCKERS_ENABLED]).delete_all
    LockerOption.lockers_enabled = true
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
    ActionMailer::Base.deliveries.clear
  end

  it "user submits a request from the new page and then sees it as pending" do
    create(:locker, specifier: "SYS-1", audience: "general")
    log_in_as(user)

    visit new_locker_rental_path
    expect(page).to have_css("h1", text: I18n.t("lockers.new_request.header"))
    expect(page).to have_text("Current lockers available are")
    expect(page).to have_select("locker_rental_requested_as", with_options: ["General request"])
    # WART(D-L05): the requested_as select starts with no
    # selected option (required), so the browser blocks submit until chosen.
    select "General request", from: "locker_rental_requested_as"
    fill_in "locker_rental_notes", with: "Close to the makerspace please"

    click_button "Submit request"

    # redirect_back with no referer falls back to the new page, which now
    # replaces the form with the pending notice
    expect(page).to have_text("You have a pending request for a locker submitted on")
    expect(page).to have_link("View current locker request")
    expect(page).not_to have_button("Submit request")
    expect(LockerRental.count).to eq(1)

    rental = LockerRental.order(:id).last
    expect(rental.rented_by).to eq(user)
    expect(rental.state).to eq("reviewing")
    expect(rental.notes).to eq("Close to the makerspace please")

    click_link "View current locker request"
    expect(page).to have_current_path(locker_rental_path(rental))
    expect(page).to have_text(I18n.t("lockers.locker_request"))
  end

  it "shows the closed notice instead of a form when lockers are disabled" do
    LockerOption.lockers_enabled = false
    log_in_as(user)
    visit new_locker_rental_path
    expect(page).to have_text("Locker requests are not currently accepted.")
    expect(page).not_to have_button("Submit request")
  end
end
