# frozen_string_literal: true

require "rails_helper"

# DOM-level characterization of the shop journey: browse proficient projects ->
# add to cart -> cart summary -> confirm order (cc points) -> orders list, and the
# membership purchase up to the external Shopify payment redirect. Real login;
# the Shopify draft order (the only external payment hop) is stubbed with a fake
# GraphQL client whose invoice URL is a local path, so the browser "arrives" at
# the payment page without leaving the app server.
RSpec.describe "Checkout", type: :system do
  let(:user) { create(:user, :regular_user) }
  let(:training) { create(:training) }
  let!(:project) { create(:proficient_project, title: "Blinky robot", cc: 40, training: training) }

  before do
    ActionMailer::Base.deliveries.clear
    block_external_http_for_system!
  end

  # System specs share the app server in-process, so a Net::HTTP#connect guard
  # would also break Capybara's own driver traffic; guard Shopify's client instead.
  def block_external_http_for_system!
    allow(ShopifyAPI::Clients::Graphql::Admin).to receive(:new) { raise "Shopify must be stubbed in this example" }
  end

  def open_training_accordion
    visit proficient_projects_path
    expect(page).to have_css("h2", text: "Proficient Projects")
    find("#header-#{training.id}").click
    expect(page).to have_css("#training-#{training.id}.show", wait: 5)
  end

  describe "cc-points order" do
    before do
      CcMoney.create!(user: user, cc: 100)
      log_in_as(user)
    end

    it "shows the price, adds the project to the cart and renders the cart summary" do
      open_training_accordion
      # projects the user has not bought are rendered in an opacity-0 wrapper (w3-opacity-max), revealed on hover
      expect(page).to have_css(".w3-opacity-max", text: "Blinky robot", visible: :all)
      expect(page).to have_css(".w3-opacity-max", text: "40 Ccs", visible: :all)
      expect(page).to have_css("input#cart-button[value='#{I18n.t('devprog.proficient_project.add')}']")

      find("#cart-button").click

      expect(page).to have_current_path(carts_path)
      expect(page).to have_css("h2", text: "Cart Summary")
      within("table.table") do
        expect(page).to have_css("thead th", count: 5)
        expect(page).to have_link("Blinky robot")
        expect(page).to have_css("tbody tr", count: 1)
        row = find("tbody tr")
        expect(row).to have_css("td:nth-child(2)", text: "1")
        expect(row).to have_css("td:nth-child(3)", text: "40")
        expect(row).to have_css("td:nth-child(4)", text: "40")
        expect(row).to have_css("form button.btn-danger i.fa-trash")
      end
      expect(page).to have_text("Order Subtotal")
      expect(page).to have_css("button[aria-label^='Confirm order, the total is 40']")
      expect(user.orders.last.order_status.name).to eq("In progress")
    end

    it "confirms the order: debits the wallet and lists a Completed order" do
      open_training_accordion
      find("#cart-button").click
      expect(page).to have_current_path(carts_path)

      # data-confirm has no JS handler wired up (turbo), so the button submits straight away
      click_button "Confirm order"

      expect(page).to have_current_path(orders_path)
      expect(page).to have_text("Your Order was successfully processed.")
      expect(page).to have_css("h2", text: "Your Orders")
      within("table.table") do
        expect(page).to have_link("Blinky robot")
        expect(page).to have_css("tbody tr", count: 1)
        expect(page).to have_text("Completed")
        expect(page).to have_css("tbody tr td:last-child", text: "40")
      end
      expect(user.reload.wallet).to eq(60)
      expect(user.cc_moneys.order(:id).last.cc).to eq(-40)
      visit carts_path
      expect(page).to have_text("There are no items in your shopping cart.")
    end

    it "blocks the confirm when the wallet is too small and keeps the cart" do
      CcMoney.create!(user: user, cc: -80) # wallet now 20 < 40
      open_training_accordion
      find("#cart-button").click
      click_button "Confirm order"

      expect(page).to have_text("Not enough Cc Points.")
      expect(user.orders.last.order_status.name).to eq("In progress")
      expect(user.orders.last.order_items.count).to eq(1)
      expect(user.reload.wallet).to eq(20)
    end

    it "an empty cart shows the empty-state copy with a link back to the projects" do
      visit carts_path
      expect(page).to have_text("There are no items in your shopping cart.")
      expect(page).to have_link("proficient projects", href: proficient_projects_path)
      expect(page).not_to have_button("Confirm order")
    end
  end

  describe "membership purchase (up to the external payment redirect)" do
    let!(:tier) do
      create(:membership_tier, title_en: "1 Semester Membership", title_fr: "Adhesion", duration: 120,
                               internal_price: 25, external_price: 40)
    end

    it "lists the tiers with prices, and submitting one lands on the (stubbed) Shopify invoice URL" do
      fake = stub_shopify_admin!
      fake.invoice_url = "/cc_moneys?from=shopify_invoice"
      user.update_column(:identity, "definitely_not_internal")
      log_in_as(user)

      visit your_memberships_memberships_path
      expect(page).to have_css("h5.card-title", text: "1 Semester Membership")
      expect(page).to have_css("p.h4", text: "$40.00")
      expect(page).to have_css("input[type=submit].btn-primary", count: 1)

      find("input[type=submit].btn-primary").click

      expect(page).to have_current_path("/cc_moneys?from=shopify_invoice")
      membership = user.memberships.last
      expect(membership.status).to eq("pending")
      expect(membership.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
      create_call = fake.calls.find { |c| c[:query].include?("draftOrderCreate") }
      expect(create_call[:variables][:input][:tags]).to eq(["makerepo_test_membership"])
    end

    it "disables the purchase buttons and warns when the user is cut off" do
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 3.years.from_now)
      log_in_as(user)
      visit your_memberships_memberships_path
      expect(page).to have_css(".alert.alert-warning", text: I18n.t("memberships.purchase.purchase.cutoff_tooltip"))
      expect(page).to have_css("input[type=submit][disabled]")
    end
  end
end
