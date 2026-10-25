# frozen_string_literal: true

require "rails_helper"

# End-to-end locker journey through the real UI (JS on), two actors
# (user + staff) in separate browser sessions. Pins the current behavior.
RSpec.describe "Journey: locker rental", type: :system do
  include ApplicationHelper

  let!(:user) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let!(:locker_a) { create(:locker, specifier: "JA-1", audience: "general") }
  let!(:locker_b) { create(:locker, specifier: "JB-2", audience: "general") }

  before do
    LockerOption.where(name: [LockerOption::LOCKER_PRODUCT_LINK, LockerOption::LOCKERS_ENABLED]).delete_all
    LockerOption.lockers_enabled = true
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
    stub_shopify_admin!
    allow_any_instance_of(CustomWebhooksController).to receive(:draft_order_metafields).and_return(nil)
    ActionMailer::Base.deliveries.clear
  end

  def request_locker_as_user(note)
    as_actor(:user) do
      log_in_as(user)
      visit new_locker_rental_path
      select "General request", from: "locker_rental_requested_as"
      fill_in "locker_rental_notes", with: note
      click_button "Submit request"
      expect(page).to have_text("You have a pending request for a locker submitted on")
    end
    LockerRental.order(:id).last
  end

  def staff_opens_request(rental)
    visit admin_locker_rentals_path
    expect(page).to have_css("h1", text: "Locker Rentals")
    expect(page).to have_text("Requests")
    within(:xpath, "//tr[.//a[normalize-space()='#{user.username}']]") { click_link "View" }
    expect(page).to have_current_path(locker_rental_path(rental))
  end

  it "request -> staff sends to checkout -> payment webhook -> active -> staff moves locker" do
    rental = request_locker_as_user("Please near the lab")
    expect(rental.state).to eq("reviewing")
    # the requested mail goes to staff, not to the user
    expect(mails_to("ceed@uottawa.ca").map(&:subject)).to eq(["New locker request"])

    as_actor(:staff) do
      log_in_as(staff)
      staff_opens_request(rental)
      expect(page).to have_text("Please near the lab")
      expect(page).to have_text("Staff Actions")
      within(:xpath, "//form[.//button[contains(normalize-space(.),'Send to Checkout')]]") do
        select "JA-1", from: "locker_rental_locker_id"
        click_button "Send to Checkout"
      end
      expect(page).to have_text("Locker rental updated")
      expect(page).to have_text("Awaiting Payment").or have_text("Await payment").or have_text(I18n.t("lockers.state.await_payment"))
    end

    rental.reload
    expect(rental.state).to eq("await_payment")
    expect(rental.locker).to eq(locker_a)
    expect(rental.decided_by).to eq(staff)
    expect(rental.owned_until).to be_present
    checkout = mails_to(user.email).last
    expect(checkout.subject).to eq("Your locker rental for locker JA-1 is ready for checkout")

    as_actor(:user) do
      visit locker_rentals_path
      expect(page).to have_text("Awaiting payment")
      click_link "Review request"
      expect(page).to have_current_path(locker_rental_path(rental))
      expect(page).to have_text(I18n.t("lockers.state.await_payment"))
    end

    # Shopify tells the app the draft order was paid.
    ActionMailer::Base.deliveries.clear
    res = post_json_to_app(orders_paid_custom_webhooks_path,
                           { tags: [LockerRental.draft_order_operating_tag],
                             metafields: [{ namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s }] })
    expect(res.code).to eq("200")

    as_actor(:user) do
      visit locker_rentals_path
      expect(page).to have_css(".badge", text: "Active")
      expect(page).to have_text("Locker #JA-1")
      click_link "View details"
      expect(page).to have_text(I18n.t("lockers.state.active"))
      expect(page).to have_text("Locker JA-1")
    end
    rental.reload
    expect(rental.state).to eq("active")
    expect(rental.paid_at).to be_present
    assigned = mails_to(user.email)
    expect(assigned.map(&:subject)).to eq(["Locker JA-1 has been assigned for you"])

    # staff moves the locker
    ActionMailer::Base.deliveries.clear
    as_actor(:staff) do
      visit locker_rental_path(rental)
      within(:xpath, "//form[.//button[contains(normalize-space(.),'Move Locker')]]") do
        select "JB-2", from: "locker_rental_locker_id"
        click_button "Move Locker"
      end
      expect(page).to have_text("Locker rental updated")
    end
    expect(rental.reload.locker).to eq(locker_b)
    expect(rental.state).to eq("active")
    moved = mails_to(user.email)
    expect(moved.map(&:subject)).to eq(["Your locker rental for Locker JB-2 has been modified"])

    as_actor(:user) do
      visit locker_rentals_path
      expect(page).to have_text("Locker #JB-2")
    end
  end

  it "request -> staff assigns directly (no payment) -> active -> staff moves locker" do
    rental = request_locker_as_user("Direct please")
    ActionMailer::Base.deliveries.clear

    as_actor(:staff) do
      log_in_as(staff)
      staff_opens_request(rental)
      within(:xpath, "//form[.//button[contains(normalize-space(.),'Assign Now')]]") do
        select "JA-1", from: "locker_rental_locker_id"
        # WART(D-E2E02): the "Indefinite" box starts checked for a request with
        # no end date, so a plain "Assign Now" makes an indefinite rental.
        expect(page).to have_checked_field("Indefinite")
        uncheck "Indefinite"
        click_button "Assign Now"
      end
      expect(page).to have_text("Locker rental updated")
      expect(page).to have_text("Move Locker")
    end
    rental.reload
    expect(rental.state).to eq("active")
    expect(rental.owned_until).to be_present
    expect(rental.locker).to eq(locker_a)
    expect(rental.decided_by).to eq(staff)
    expect(rental.paid_at).to be_nil
    expect(mails_to(user.email).map(&:subject)).to eq(["Locker JA-1 has been assigned for you"])

    as_actor(:user) do
      visit locker_rentals_path
      expect(page).to have_css(".badge", text: "Active")
      expect(page).to have_text("Locker #JA-1")
    end

    ActionMailer::Base.deliveries.clear
    as_actor(:staff) do
      within(:xpath, "//form[.//button[contains(normalize-space(.),'Move Locker')]]") do
        select "JB-2", from: "locker_rental_locker_id"
        click_button "Move Locker"
      end
      expect(page).to have_text("Locker rental updated")
    end
    expect(rental.reload.locker).to eq(locker_b)
    expect(mails_to(user.email).map(&:subject)).to eq(["Your locker rental for Locker JB-2 has been modified"])
    as_actor(:user) do
      visit locker_rentals_path
      expect(page).to have_text("Locker #JB-2")
    end
  end

  it "staff assigns a locker to a user from the admin assign form (no request)" do
    as_actor(:staff) do
      log_in_as(staff)
      visit assign_locker_locker_rentals_path
      expect(page).to have_css("h1", text: "Assign locker to a user")
      select "#{user.name} (#{user.username})", from: "locker_rental_rented_by_id"
      select "#JB-2", from: "locker_rental_locker_id", match: :prefer_exact
      click_button "Assign Locker"
      expect(page).to have_text("Locker assigned")
    end
    rental = LockerRental.order(:id).last
    expect(rental.rented_by).to eq(user)
    expect(rental.state).to eq("active")
    expect(rental.locker).to eq(locker_b)
    expect(mails_to(user.email).map(&:subject)).to eq(["Locker JB-2 has been assigned for you"])
    as_actor(:user) do
      log_in_as(user)
      visit locker_rentals_path
      expect(page).to have_text("Locker #JB-2")
    end
  end

  it "pinned: plain Assign Now makes an indefinite rental and the user's locker index 500s" do
    rental = request_locker_as_user("Indefinite by default")
    as_actor(:staff) do
      log_in_as(staff)
      staff_opens_request(rental)
      within(:xpath, "//form[.//button[contains(normalize-space(.),'Assign Now')]]") do
        select "JA-1", from: "locker_rental_locker_id"
        click_button "Assign Now"
      end
      expect(page).to have_text("Locker rental updated")
    end
    rental.reload
    expect(rental.state).to eq("active")
    expect(rental.owned_until).to be_nil

    as_actor(:user) do
      # WART(D-E2E01): index.html.erb calls owned_until.to_date on an active
      # rental with no end date: the whole page 500s for the renter.
      visit locker_rentals_path
      expect(page).to have_no_css("nav.navbar")
      expect(page).to have_text("NoMethodError in LockerRentals#index")
      # the detail page still renders it
      visit locker_rental_path(rental)
      expect(page).to have_text(/indefinite rental/i)
      expect(page).to have_text(/does not expire/i)
    end
    expect(mails_to(user.email).map(&:subject)).to eq(["Locker JA-1 has been assigned for you"])
  end
end
