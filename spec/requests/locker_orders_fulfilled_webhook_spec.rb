# frozen_string_literal: true

require "rails_helper"

# Shopify `orders_fulfilled` webhook: a cash locker order is fulfilled by staff without being marked paid,
# so the fulfillment records the locker payment. Only the locker branch runs, and only while the payment is
# pending. Every POST is signed (spec/support/shopify_webhook_helpers.rb); the Shopify metafield lookup is stubbed.
RSpec.describe "Shopify orders_fulfilled webhook (cash lockers)", type: :request do
  include ActiveJob::TestHelper

  # The webhook stores the order and queues ApplyProcessedOrderJob; the job runs inline here, as the queue would.
  def deliver_paid(params, **opts)
    perform_enqueued_jobs(only: [ApplyProcessedOrderJob, ActionMailer::MailDeliveryJob]) { signed_orders_paid(params, **opts) }
  end

  def deliver_fulfilled(params, **opts)
    perform_enqueued_jobs(only: [ApplyProcessedOrderJob, ActionMailer::MailDeliveryJob]) { signed_orders_fulfilled(params, **opts) }
  end
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
    allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields).and_return(nil)
  end

  it "activates an await_payment rental and records one applied payment for a pending (cash) order" do
    rental = create(:locker_rental, :await_payment)

    deliver_fulfilled(payload(rental.id))

    expect(response).to have_http_status(:ok)
    expect(rental.reload).to be_active
    expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status))
      .to eq([[order_id.to_s, "applied"]])
  end

  it "dates the payment at the fulfilment (when the cash was taken), not at the order's creation" do
    rental = create(:locker_rental, :await_payment)

    deliver_fulfilled(payload(rental.id, processed_at: "2026-10-01T12:00:00Z",
                                               fulfillments: [{ created_at: "2026-10-20T15:30:00Z" }]))

    expect(LockerPayment.find_by!(locker_rental: rental).paid_at).to eq(Time.utc(2026, 10, 20, 15, 30))
  end

  %w[paid refunded voided partially_paid partially_refunded authorized].each do |status|
    it "applies nothing for a #{status} order (200)" do
      rental = create(:locker_rental, :await_payment)

      deliver_fulfilled(payload(rental.id, financial_status: status))

      expect(response).to have_http_status(:ok)
      expect(rental.reload).not_to be_active
      expect(LockerPayment.where(locker_rental: rental)).to be_empty
    end
  end

  it "applies nothing for an order without the locker tag" do
    rental = create(:locker_rental, :await_payment)

    deliver_fulfilled(payload(rental.id, tags: ["makerepo_locker"]))

    expect(response).to have_http_status(:ok)
    expect(rental.reload).not_to be_active
  end

  it "leaves cash memberships and CC Money to staff" do
    user = create(:user, :regular_user)
    membership = create(:membership, user: user, status: :pending)

    expect do
      deliver_fulfilled({
        id: order_id, financial_status: "pending", tags: [Membership.draft_order_operating_tag],
        customer: { email: user.email },
        line_items: [{ product_id: 4_359_597_129_784, quantity: 2, title: membership.membership_tier.title_en }],
        metafields: [{ namespace: "makerepo", key: "membership_db_reference", value: membership.id.to_s }]
      })
    end.not_to change(CcMoney, :count)

    expect(response).to have_http_status(:ok)
    expect(membership.reload.status).to eq("pending")
  end

  it "is not applied again when the same order is later marked paid (orders_paid)" do
    rental = create(:locker_rental, :await_payment)
    deliver_fulfilled(payload(rental.id))
    expect(rental.reload).to be_active

    deliver_paid(payload(rental.id, financial_status: "paid"))

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

  # One run as the dispatcher starts it: the order is leased and the job carries the lease as its token.
  def run_leased_job(order)
    token = (Time.current + ProcessedOrder::LEASE).floor(6)
    ProcessedOrder.where(id: order.id).update_all(leased_until: token)
    ApplyProcessedOrderJob.perform_now(order.id, token)
  end

  it "answers 200 and stores the order when Shopify is not configured; the job retries it" do
    rental = create(:locker_rental, :await_payment)
    allow_any_instance_of(ShopOrderApplier).to receive(:resolve_references).and_raise(ShopifyContext::NotConfigured)

    signed_orders_fulfilled(payload(rental.id))
    expect(response).to have_http_status(:ok)
    stored = ProcessedOrder.find_by!(provider_ref: "#{order_id}/fulfilled")
    expect(stored).to have_attributes(topic: "orders/fulfilled", status: "received")

    run_leased_job(stored)
    expect(stored.reload).to have_attributes(status: "received", attempts: 1)
    expect(rental.reload).not_to be_active

    allow_any_instance_of(ShopOrderApplier).to receive(:resolve_references).and_call_original
    run_leased_job(stored)
    expect([stored.reload.status, rental.reload.state]).to eq(["applied", "active"])
  end

  it "applies a later orders/paid of the same order too: the two deliveries are separate units, the locker is paid once" do
    rental = create(:locker_rental, :await_payment)
    member = create(:user, :regular_user)
    pending = create(:membership, user: member, membership_tier: create(:membership_tier), status: "pending")
    paid = payload(rental.id, financial_status: "paid").merge(
      tags: [tag, Membership.draft_order_operating_tag], line_items: [{ title: "x", quantity: 1 }],
      metafields: [{ namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s },
                   { namespace: "makerepo", key: "membership_db_reference", value: pending.id.to_s }]
    )

    deliver_fulfilled(payload(rental.id).merge(tags: [tag]))
    deliver_paid(paid)

    expect(ProcessedOrder.order(:id).pluck(:provider_ref, :status))
      .to eq([["#{order_id}/fulfilled", "applied"], [order_id.to_s, "applied"]])
    expect(LockerPayment.where(locker_rental: rental).count).to eq(1)
    expect(pending.reload.status).to eq("paid")
  end

  it "applies the locker once when orders/paid arrives before the orders/fulfilled path" do
    rental = create(:locker_rental, :await_payment)

    deliver_paid(payload(rental.id, financial_status: "paid"))
    deliver_fulfilled(payload(rental.id))

    expect(LockerPayment.where(locker_rental: rental).count).to eq(1)
    expect(ProcessedOrder.order(:id).pluck(:status)).to eq(%w[applied applied])
  end
end
