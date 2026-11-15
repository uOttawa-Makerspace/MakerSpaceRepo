# frozen_string_literal: true

require "rails_helper"

# Every path that creates, replaces or removes a locker rental's Shopify draft, or records and settles a locker
# payment, end to end: the card payment (orders/paid), the cash payment (orders/fulfilled), a retried delivery,
# held payments refunded, dismissed or settled by an assignment, the checkout link (a new draft, a replaced one),
# the draft removed when a rental is cancelled or starts a new term, and the draft sweep. Each example pins what
# the rental and payment columns become.
RSpec.describe "Locker payment records", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:tag) { LockerRental.draft_order_operating_tag }
  let(:gid) { "gid://shopify/DraftOrder/9001" }
  let(:frozen) { Time.utc(2026, 10, 20, 12) }
  let(:staff) { create(:user, :staff) }

  before do
    ActionMailer::Base.deliveries.clear
    allow_any_instance_of(ShopOrderApplier).to receive(:draft_order_metafields).and_return(nil)
  end

  def payload(rental, id:, **extra)
    { id: id, tags: [tag], total_price: "20.00", currency: "CAD",
      line_items: [{ title: "TEST locker on #{Rails.env} environment.", price: "20.00", quantity: 1 }],
      metafields: [{ namespace: "makerepo", key: "locker_db_reference", value: rental.id.to_s }] }.merge(extra)
  end

  def deliver(topic, params)
    travel_to(frozen) do
      perform_enqueued_jobs(only: [ApplyProcessedOrderJob, ApplicationMailer.delivery_job]) do
        topic == :paid ? signed_orders_paid(params) : signed_orders_fulfilled(params)
      end
    end
    expect(response).to have_http_status(:ok)
  end

  def with_draft(rental, draft = gid)
    rental.update_column(:shopify_draft_order_id, draft)
    rental.reload
  end

  def resolve(payment, resolution)
    LockerRental.transaction do
      payment.locker_rental.lock!
      payment.resolve!(resolution, by: staff, note: "settled")
    end
  end

  describe "a paid order" do
    it "by card activates the rental, keeps its draft id and records one applied payment" do
      rental = with_draft(create(:locker_rental, :await_payment))
      deliver(:paid, payload(rental, id: 5001))

      expect(rental.reload).to have_attributes(state: "active", paid_at: frozen, shopify_draft_order_id: gid)
      expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status, :amount))
        .to eq([["5001", "applied", BigDecimal("20.00")]])
    end

    it "in cash (fulfilled, pending) activates the rental and records one applied payment" do
      rental = with_draft(create(:locker_rental, :await_payment))
      deliver(:fulfilled, payload(rental, id: 5002, financial_status: "pending"))

      expect(rental.reload).to have_attributes(state: "active", shopify_draft_order_id: gid)
      expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status)).to eq([%w[5002 applied]])
    end

    it "delivered twice records one payment" do
      rental = with_draft(create(:locker_rental, :await_payment))
      2.times { deliver(:paid, payload(rental, id: 5003)) }
      2.times { deliver(:fulfilled, payload(rental, id: 5003, financial_status: "pending")) }

      expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status)).to eq([%w[5003 applied]])
    end
  end

  describe "a held payment" do
    let(:rental) { create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) } }

    before { deliver(:paid, payload(rental, id: 5004)) }

    let(:payment) { LockerPayment.find_by!(shopify_order_id: "5004") }

    it "is recorded held, and refunded by staff" do
      expect(payment).to have_attributes(status: "held", hold_reason: "rental_cancelled", resolved_at: nil)
      expect(resolve(payment, "refunded")).to be(true)
      expect(payment.reload).to have_attributes(status: "refunded", resolved_by_id: staff.id, resolution_note: "settled")
      expect(resolve(payment, "refunded")).to be(false)
    end

    it "is dismissed by staff" do
      expect(resolve(payment, "dismissed")).to be(true)
      expect(payment.reload).to have_attributes(status: "dismissed", resolved_by_id: staff.id)
    end
  end

  it "settles a held payment when staff assign the rental active" do
    rental = with_draft(create(:locker_rental, :await_payment))
    rental.rented_by.deactivate!
    deliver(:paid, payload(rental, id: 5005))
    payment = LockerPayment.find_by!(shopify_order_id: "5005")
    expect(payment).to have_attributes(status: "held", hold_reason: "renter_ineligible")

    rental.rented_by.reload.reactivate!
    LockerRental.transaction do
      rental.lock!
      rental.update!(state: :active, decided_by: staff)
      expect(rental.settle_held_payments!(by: staff)).to eq(1)
    end
    expect(payment.reload.status).to eq("applied")
    expect(rental.reload).to have_attributes(state: "active", paid_at: frozen, shopify_draft_order_id: gid)
  end

  describe "the checkout link" do
    let!(:fake) { stub_shopify_admin!.tap { |f| f.draft_id = gid } }

    it "creates and stores a draft for a rental awaiting payment" do
      rental = create(:locker_rental, :await_payment)
      expect(rental.checkout_link).to eq(fake.invoice_url)
      expect(rental.reload.shopify_draft_order_id).to eq(gid)
    end

    it "replaces a stored draft Shopify no longer has" do
      rental = with_draft(create(:locker_rental, :await_payment), "gid://shopify/DraftOrder/1")
      fake.missing_ids << "gid://shopify/DraftOrder/1"
      expect(rental.checkout_link).to eq(fake.invoice_url)
      expect(rental.reload.shopify_draft_order_id).to eq(gid)
    end
  end

  describe "the draft of a rental that ends or starts a new term" do
    let!(:fake) { stub_shopify_admin!.tap { |f| f.draft_id = gid } }

    it "is deleted and forgotten when the rental is cancelled" do
      rental = with_draft(create(:locker_rental, :await_payment))
      rental.update!(state: :cancelled, decided_by: staff)
      expect(rental.sync_shopify_draft_order_after_commit).to be(true)
      expect(rental.reload.shopify_draft_order_id).to be_nil
    end

    it "is kept when it was paid and the rental ends, and forgotten when a paid rental starts a new term" do
      fake.delete_user_errors = [{ "field" => "id", "message" => "completed" }]
      fake.draft_statuses[gid] = "COMPLETED"
      ended = with_draft(create(:locker_rental, :active))
      ended.update!(state: :cancelled)
      expect(ended.sync_shopify_draft_order_after_commit).to be(true)
      expect(ended.reload.shopify_draft_order_id).to eq(gid)

      renewed = with_draft(create(:locker_rental, :active), "gid://shopify/DraftOrder/2")
      fake.draft_statuses["gid://shopify/DraftOrder/2"] = "COMPLETED"
      renewed.update!(state: :await_payment)
      expect(renewed.sync_shopify_draft_order_after_commit).to be(true)
      expect(renewed.reload.shopify_draft_order_id).to be_nil
    end
  end

  it "the draft sweep deletes and forgets a stored draft the rental no longer backs" do
    fake = stub_shopify_admin!.tap { |f| f.draft_id = gid }
    rental = with_draft(create(:locker_rental, :active))
    fake.draft_pages = [[{ "id" => gid, "status" => "OPEN", "tags" => [tag, "locker_rental:#{rental.id}"] }]]
    outcome = LockerRental.reconcile_orphan_draft!(rental.id, gid, may_delete: true)
    expect(outcome).to have_attributes(value: :deleted)
    expect(rental.reload.shopify_draft_order_id).to be_nil
  end
end
