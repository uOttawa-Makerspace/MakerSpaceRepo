# frozen_string_literal: true

require "rails_helper"

# Shopify `orders_fulfilled` webhook: a cash locker order is fulfilled by staff without being marked paid,
# so the fulfillment records the locker payment. Only the locker branch runs, and only while the payment is
# pending. Every POST is signed (spec/support/shopify_webhook_helpers.rb); the Shopify metafield lookup is stubbed.
RSpec.describe "Shopify orders_fulfilled webhook (cash lockers)", type: :request do
  let(:tag) { LockerRental.draft_order_operating_tag }
  let(:order_id) { 820_982_911_946_154_509 }

  def payload(rental_id, financial_status: "pending", tags: [tag], **extra)
    {
      id: order_id,
      financial_status: financial_status,
      tags: tags,
      metafields: [{ namespace: "makerepo", key: "locker_db_reference", value: rental_id.to_s }]
    }.merge(extra)
  end

  before do
    allow_any_instance_of(CustomWebhooksController).to receive(:draft_order_metafields).and_return(nil)
  end

  it "activates an await_payment rental and records one applied payment for a pending (cash) order" do
    rental = create(:locker_rental, :await_payment)

    signed_orders_fulfilled(payload(rental.id))

    expect(response).to have_http_status(:ok)
    expect(rental.reload).to be_active
    expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status))
      .to eq([[order_id.to_s, "applied"]])
  end

  it "dates the payment at the fulfilment (when the cash was taken), not at the order's creation" do
    rental = create(:locker_rental, :await_payment)

    signed_orders_fulfilled(payload(rental.id, processed_at: "2026-10-01T12:00:00Z",
                                               fulfillments: [{ created_at: "2026-10-20T15:30:00Z" }]))

    expect(LockerPayment.find_by!(locker_rental: rental).paid_at).to eq(Time.utc(2026, 10, 20, 15, 30))
  end

  %w[paid refunded voided partially_paid partially_refunded authorized].each do |status|
    it "applies nothing for a #{status} order (200)" do
      rental = create(:locker_rental, :await_payment)

      signed_orders_fulfilled(payload(rental.id, financial_status: status))

      expect(response).to have_http_status(:ok)
      expect(rental.reload).not_to be_active
      expect(LockerPayment.where(locker_rental: rental)).to be_empty
    end
  end

  it "applies nothing for an order without the locker tag" do
    rental = create(:locker_rental, :await_payment)

    signed_orders_fulfilled(payload(rental.id, tags: ["makerepo_locker"]))

    expect(response).to have_http_status(:ok)
    expect(rental.reload).not_to be_active
  end

  it "leaves cash memberships and CC Money to staff" do
    user = create(:user, :regular_user)
    membership = create(:membership, user: user, status: :pending)

    expect do
      signed_orders_fulfilled(
        id: order_id, financial_status: "pending", tags: [Membership.draft_order_operating_tag],
        customer: { email: user.email },
        line_items: [{ product_id: 4_359_597_129_784, quantity: 2, title: membership.membership_tier.title_en }],
        metafields: [{ namespace: "makerepo", key: "membership_db_reference", value: membership.id.to_s }]
      )
    end.not_to change(CcMoney, :count)

    expect(response).to have_http_status(:ok)
    expect(membership.reload.status).to eq("pending")
  end

  it "is not applied again when the same order is later marked paid (orders_paid)" do
    rental = create(:locker_rental, :await_payment)
    signed_orders_fulfilled(payload(rental.id))
    expect(rental.reload).to be_active

    signed_orders_paid(payload(rental.id, financial_status: "paid"))

    expect(response).to have_http_status(:ok)
    expect(LockerPayment.where(locker_rental: rental).count).to eq(1)
  end

  it "rejects an unsigned delivery (401) and applies nothing" do
    rental = create(:locker_rental, :await_payment)
    body = payload(rental.id).to_json

    post orders_fulfilled_custom_webhooks_path, params: body, headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
    expect(rental.reload).not_to be_active
  end

  it "answers 503 when Shopify is not configured, so Shopify retries" do
    rental = create(:locker_rental, :await_payment)
    allow_any_instance_of(CustomWebhooksController)
      .to receive(:locker_reference).and_raise(ShopifyContext::NotConfigured)

    signed_orders_fulfilled(payload(rental.id))

    expect(response).to have_http_status(:service_unavailable)
    expect(rental.reload).not_to be_active
  end
end
