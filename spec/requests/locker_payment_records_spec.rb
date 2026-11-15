# frozen_string_literal: true

require "rails_helper"

# Every path that creates, replaces or removes a locker rental's Shopify draft, or records and settles a locker
# payment, end to end: the card payment (orders/paid), the cash payment (orders/fulfilled), a retried delivery,
# held payments refunded, dismissed or settled by an assignment, the checkout link (a new draft, a replaced one),
# the draft removed when a rental is cancelled or starts a new term, and the draft sweep. Each example pins what
# the rental and payment columns become, and the payment checkout records and ledger entries written beside them.
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

  # A stored draft with its open checkout record, as storing a new draft writes them.
  def with_draft(rental, draft = gid)
    rental.transaction do
      rental.update_column(:shopify_draft_order_id, draft)
      rental.open_checkout_record(draft)
    end
    rental.reload
  end

  def checkouts(rental)
    PaymentCheckout.where(reference: rental).order(:id).pluck(:provider, :provider_id, :status, :term)
  end

  def ledger(payment)
    PaymentLedgerEntry.where(provider_ref: payment.shopify_order_id).order(:id)
                      .pluck(:provider, :kind, :amount, :reversed_entry_id)
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

      payment = LockerPayment.find_by!(shopify_order_id: "5001")
      expect(checkouts(rental)).to eq([["shopify", gid, "paid", rental.owned_until.to_date]])
      expect(ledger(payment)).to eq([["shopify", "payment", BigDecimal("20.00"), nil]])
      expect(payment.ledger_entry).to have_attributes(provider_ref: "5001", kind: "payment")
      expect(payment.reversed_at).to be_nil
    end

    it "in cash (fulfilled, pending) activates the rental and records one applied payment" do
      rental = with_draft(create(:locker_rental, :await_payment))
      deliver(:fulfilled, payload(rental, id: 5002, financial_status: "pending"))

      expect(rental.reload).to have_attributes(state: "active", shopify_draft_order_id: gid)
      expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status)).to eq([%w[5002 applied]])

      payment = LockerPayment.find_by!(shopify_order_id: "5002")
      expect(checkouts(rental).map(&:third)).to eq(%w[paid])
      expect(ledger(payment)).to eq([["shopify", "payment", BigDecimal("20.00"), nil]])
      expect(payment.ledger_entry_id).to be_present
    end

    it "delivered twice records one payment" do
      rental = with_draft(create(:locker_rental, :await_payment))
      2.times { deliver(:paid, payload(rental, id: 5003)) }
      2.times { deliver(:fulfilled, payload(rental, id: 5003, financial_status: "pending")) }

      expect(LockerPayment.where(locker_rental: rental).pluck(:shopify_order_id, :status)).to eq([%w[5003 applied]])

      expect(PaymentLedgerEntry.where(provider_ref: "5003").pluck(:kind)).to eq(%w[payment])
      expect(checkouts(rental).map(&:third)).to eq(%w[paid])
    end
  end

  describe "a held payment" do
    let(:rental) { create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) } }

    before { deliver(:paid, payload(rental, id: 5004)) }

    let(:payment) { LockerPayment.find_by!(shopify_order_id: "5004") }

    it "is recorded held, and refunded by staff" do
      expect(payment).to have_attributes(status: "held", hold_reason: "rental_cancelled", resolved_at: nil)
      expect(ledger(payment)).to eq([["shopify", "payment", BigDecimal("20.00"), nil]])
      refunded_at = Time.utc(2026, 10, 21, 9)
      travel_to(refunded_at) { expect(resolve(payment, "refunded")).to be(true) }
      expect(payment.reload).to have_attributes(status: "refunded", resolved_by_id: staff.id, resolution_note: "settled")
      expect(resolve(payment, "refunded")).to be(false)

      expect(payment.reversed_at).to eq(refunded_at)
      expect(ledger(payment)).to eq([["shopify", "payment", BigDecimal("20.00"), nil],
                                     ["shopify", "reversal", BigDecimal("20.00"), payment.ledger_entry_id]])
    end

    it "is dismissed by staff" do
      expect(resolve(payment, "dismissed")).to be(true)
      expect(payment.reload).to have_attributes(status: "dismissed", resolved_by_id: staff.id)

      expect(payment.reversed_at).to be_nil
      expect(ledger(payment).map(&:second)).to eq(%w[payment])
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

    expect(checkouts(rental).map(&:third)).to eq(%w[paid])
    expect(ledger(payment).map(&:second)).to eq(%w[payment])
  end

  describe "the checkout link" do
    let!(:fake) { stub_shopify_admin!.tap { |f| f.draft_id = gid } }

    it "creates and stores a draft for a rental awaiting payment" do
      rental = create(:locker_rental, :await_payment)
      expect(rental.checkout_link).to eq(fake.invoice_url)
      expect(rental.reload.shopify_draft_order_id).to eq(gid)

      expect(checkouts(rental)).to eq([["shopify", gid, "open", rental.owned_until.to_date]])
    end

    it "replaces a stored draft Shopify no longer has" do
      rental = with_draft(create(:locker_rental, :await_payment), "gid://shopify/DraftOrder/1")
      fake.missing_ids << "gid://shopify/DraftOrder/1"
      expect(rental.checkout_link).to eq(fake.invoice_url)
      expect(rental.reload.shopify_draft_order_id).to eq(gid)

      expect(checkouts(rental).map { |c| c.values_at(1, 2) })
        .to eq([["gid://shopify/DraftOrder/1", "void"], [gid, "open"]])
    end
  end

  describe "the draft of a rental that ends or starts a new term" do
    let!(:fake) { stub_shopify_admin!.tap { |f| f.draft_id = gid } }

    it "is deleted and forgotten when the rental is cancelled" do
      rental = with_draft(create(:locker_rental, :await_payment))
      rental.update!(state: :cancelled, decided_by: staff)
      expect(rental.sync_shopify_draft_order_after_commit).to be(true)
      expect(rental.reload.shopify_draft_order_id).to be_nil

      expect(checkouts(rental).map(&:third)).to eq(%w[void])
    end

    it "is kept when it was paid and the rental ends, and forgotten when a paid rental starts a new term" do
      fake.delete_user_errors = [{ "field" => "id", "message" => "completed" }]
      fake.draft_statuses[gid] = "COMPLETED"
      ended = with_draft(create(:locker_rental, :active))
      ended.update!(state: :cancelled)
      expect(ended.sync_shopify_draft_order_after_commit).to be(true)
      expect(ended.reload.shopify_draft_order_id).to eq(gid)
      expect(checkouts(ended).map(&:third)).to eq(%w[paid])

      renewed = with_draft(create(:locker_rental, :active), "gid://shopify/DraftOrder/2")
      fake.draft_statuses["gid://shopify/DraftOrder/2"] = "COMPLETED"
      renewed.update!(state: :await_payment)
      expect(renewed.sync_shopify_draft_order_after_commit).to be(true)
      expect(renewed.reload.shopify_draft_order_id).to be_nil
      expect(checkouts(renewed).map(&:third)).to eq(%w[paid])
    end
  end

  it "the draft sweep deletes and forgets a stored draft the rental no longer backs" do
    fake = stub_shopify_admin!.tap { |f| f.draft_id = gid }
    rental = with_draft(create(:locker_rental, :active))
    fake.draft_pages = [[{ "id" => gid, "status" => "OPEN", "tags" => [tag, "locker_rental:#{rental.id}"] }]]
    outcome = LockerRental.reconcile_orphan_draft!(rental.id, gid, may_delete: true)
    expect(outcome).to have_attributes(value: :deleted)
    expect(rental.reload.shopify_draft_order_id).to be_nil

    expect(checkouts(rental).map(&:third)).to eq(%w[void])
  end

  it "opens a checkout with no term for a rental without an end date, and pays nothing for a rental without a draft" do
    rental = create(:locker_rental, :await_payment)
    rental.update_column(:owned_until, nil)
    with_draft(rental.reload)
    expect(checkouts(rental)).to eq([["shopify", gid, "open", nil]])

    no_draft = create(:locker_rental, :active)
    no_draft.record_payment(shopify_order_id: "5008")
    expect(checkouts(no_draft)).to be_empty
  end

  describe "a checkout or ledger row already there" do
    let(:check_adapter) { instance_double(Payments::ShopifyAdapter) }
    let(:reports) { [] }

    before { allow(Rails.error).to receive(:report) { |error, **opts| reports << opts.dig(:context, :check) } }

    def checked = LockerRental::PaymentRecordsCheck.run(adapter: check_adapter)

    it "a new draft whose id another checkout already records is reported and not served, and nothing is stored" do
      fake = stub_shopify_admin!.tap { |f| f.draft_id = gid }
      PaymentCheckout.create!(reference: create(:locker_rental), provider: "shopify", provider_id: gid, status: :void)
      rental = create(:locker_rental, :await_payment)
      errors = []
      allow(Rails.error).to receive(:report) { |error, **| errors << error }

      expect(rental.checkout_link).to be_nil
      expect(errors).to contain_exactly(be_a(ActiveRecord::RecordNotUnique))
      expect(rental.reload.shopify_draft_order_id).to be_nil
      expect(fake.deleted_ids).to be_empty
      expect(checkouts(rental)).to eq([["shopify", nil, "open", rental.owned_until.to_date]])
    end

    it "never fails a payment: it links an existing entry, and the check reports a different amount" do
      PaymentLedgerEntry.record_payment(provider: "shopify", provider_ref: "5010", amount: BigDecimal("1.00"))
      rental = with_draft(create(:locker_rental, :await_payment))
      deliver(:paid, payload(rental, id: 5010))

      payment = LockerPayment.find_by!(shopify_order_id: "5010")
      expect(payment).to have_attributes(status: "applied", amount: BigDecimal("20.00"))
      expect(ledger(payment)).to eq([["shopify", "payment", BigDecimal("1.00"), nil]])
      expect(payment.ledger_entry_id).to eq(PaymentLedgerEntry.find_by!(provider_ref: "5010").id)
      expect(checked).to eq("ledger_entry_differs" => [payment.id])
    end

    it "never fails a payment or its refund when the entry belongs to another payment: the check reports it" do
      entry = PaymentLedgerEntry.record_payment(provider: "shopify", provider_ref: "5011", amount: nil)
      expect(entry).to be_persisted
      other = create(:locker_rental, :active).record_payment(shopify_order_id: "5012")
      LockerPayment.where(id: other.id).update_all(ledger_entry_id: entry.id)
      rental = create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }

      payment = rental.record_payment(shopify_order_id: "5011")
      expect(payment).to have_attributes(status: "held", ledger_entry_id: nil)
      expect(resolve(payment, "refunded")).to be(true)
      expect(payment.reload).to have_attributes(status: "refunded", reversed_at: be_present, ledger_entry_id: nil)
      expect(PaymentLedgerEntry.where(provider_ref: "5011").pluck(:kind)).to eq(%w[payment])
      expect(checked).to include("ledger_entry_missing" => [payment.id], "reversal_differs" => [payment.id])
    end
  end

  it "voids the claim of a draft that is not kept (the rental was cancelled while Shopify made it)" do
    fake = stub_shopify_admin!.tap { |f| f.draft_id = gid }
    rental = create(:locker_rental, :await_payment)
    fake.on_query = lambda do |query, _|
      LockerRental.where(id: rental.id).update_all(state: "cancelled", cancelled_at: Time.current) if query.include?("draftOrderCreate")
    end
    expect(rental.checkout_link).to be_nil
    expect(fake.deleted_ids).to eq([gid])
    expect(checkouts(rental)).to eq([["shopify", nil, "void", rental.owned_until.to_date]])
  end

  it "pays the checkout of the draft the row stores now, even through a stale rental instance" do
    rental = create(:locker_rental, :await_payment)
    rental.rented_by.deactivate!
    payment = rental.record_payment(shopify_order_id: "5013")
    stale = payment.locker_rental # loaded with no draft
    expect(stale.shopify_draft_order_id).to be_nil
    with_draft(LockerRental.find(rental.id))
    rental.rented_by.reload.reactivate!

    stale.record_checkout_paid
    expect(checkouts(rental).map(&:third)).to eq(%w[paid])
    expect(payment.mark_applied!(by: staff)).to be(true)
  end

  describe "the ledger writers on a retry" do
    let(:payment) do
      rental = create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }
      rental.record_payment(shopify_order_id: "5006", amount: "3.00")
    end

    it "write one payment entry and link it once" do
      entry_id = payment.ledger_entry_id
      expect(payment.record_in_ledger.id).to eq(entry_id)
      expect(PaymentLedgerEntry.record_payment(provider: "shopify", provider_ref: "5006", amount: BigDecimal("3.00")).id)
        .to eq(entry_id)
      expect(LockerPayment.find(payment.id).record_in_ledger.id).to eq(entry_id)
      expect(ledger(payment).map(&:second)).to eq(%w[payment])
    end

    it "write one reversal" do
      2.times { PaymentLedgerEntry.record_reversal(payment.ledger_entry) }
      expect(ledger(payment).map(&:second)).to eq(%w[payment reversal])
    end

    it "write the payment entry first when a payment without one is refunded" do
      rental = create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }
      bare = LockerPayment.find(LockerPayment.insert(
        { locker_rental_id: rental.id, shopify_order_id: "5007", paid_at: Time.current, status: "held",
          hold_reason: "rental_cancelled" }, returning: %w[id]
      ).rows.first.first)
      expect(resolve(bare, "refunded")).to be(true)
      expect(ledger(bare).map(&:second)).to eq(%w[payment reversal])
      expect(bare.reload.ledger_entry_id).to be_present
    end
  end
end
