# frozen_string_literal: true

require "rails_helper"

RSpec.describe LockerRental::PaymentRecordsCheck, type: :model do
  let(:adapter) { instance_double(Payments::ShopifyAdapter) }
  let(:reports) { [] }

  before { allow(Rails.error).to receive(:report) { |error, **opts| reports << [error, opts] } }

  def run = described_class.run(adapter: adapter)

  def reported
    reports.to_h { |error, opts| [opts.dig(:context, :check), opts.dig(:context, :ids)] }
  end

  def stored_draft(rental, gid)
    rental.transaction do
      rental.update_column(:shopify_draft_order_id, gid)
      rental.open_checkout_record(gid)
    end
    rental
  end

  def paid_rental(order_id)
    rental = create(:locker_rental, :await_payment)
    stored_draft(rental, "gid://shopify/DraftOrder/#{order_id}")
    rental.record_payment(shopify_order_id: order_id, amount: "5.00")
    rental
  end

  it "reports nothing and asks Shopify nothing when the records match" do
    paid_rental("1")
    stored_draft(create(:locker_rental, :await_payment), "gid://shopify/DraftOrder/2")
    refunded = paid_rental("3").tap { |r| r.update!(state: :cancelled) }.locker_payments.first
    LockerPayment.where(id: refunded.id).update_all(status: "held", hold_reason: "rental_cancelled", resolved_at: nil)
    refunded.reload.resolve!("refunded", by: create(:user, :staff))

    expect(run).to be_empty
    expect(reports).to be_empty
  end

  it "reports each planted difference once, with ids only" do
    missing = create(:locker_rental, :await_payment).tap { |r| r.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/10") }
    open_on_active = paid_rental("11")
    differs = PaymentCheckout.find_by!(reference: open_on_active)
    differs.update_column(:status, "open")
    stray = PaymentCheckout.create!(reference: create(:locker_rental), provider: "shopify", provider_id: "gid://shopify/DraftOrder/12")
    unlinked = paid_rental("13").locker_payments.first.tap { |p| p.update_column(:ledger_entry_id, nil) }
    other_amount = paid_rental("14").locker_payments.first.tap { |p| p.update_column(:amount, BigDecimal("9.00")) }
    not_reversed = paid_rental("15").locker_payments.first.tap { |p| p.update_columns(status: "refunded") }

    run

    expect(reported).to eq(
      "checkout_missing" => [missing.id],
      "checkout_status_differs" => [differs.id],
      "open_checkout_not_stored" => [stray.id],
      "ledger_entry_missing" => [unlinked.id],
      "ledger_entry_differs" => [other_amount.id],
      "reversal_differs" => [not_reversed.id]
    )
    error, opts = reports.first
    expect(error).to be_a(described_class::Difference)
    expect(error.message).to eq("locker payment records differ: checkout_missing")
    expect(opts).to eq(handled: true, severity: :error, context: { check: "checkout_missing", count: 1, ids: [missing.id] })
  end

  it "changes no old column and no checked row" do
    rental = create(:locker_rental, :await_payment).tap { |r| r.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/20") }
    payment = paid_rental("21").locker_payments.first.tap { |p| p.update_column(:ledger_entry_id, nil) }
    expect { run }.not_to(change { [rental.reload.attributes, payment.reload.attributes, PaymentCheckout.count, PaymentLedgerEntry.count] })
  end

  describe "a stored draft the rental's data does not settle" do
    let(:gid) { "gid://shopify/DraftOrder/30" }
    let(:rental) { create(:locker_rental, :active).tap { |r| r.update_column(:shopify_draft_order_id, gid) } }

    { paid: "paid", open: "open", gone: "void" }.each do |answer, status|
      it "is recorded #{status} when Shopify answers #{answer}" do
        allow(adapter).to receive(:checkout_status).with(gid).and_return(answer)
        rental
        expect(run).to be_empty
        expect(PaymentCheckout.where(reference: rental).pluck(:provider_id, :status, :term))
          .to eq([[gid, status, rental.owned_until.to_date]])
        expect(rental.reload.shopify_draft_order_id).to eq(gid)
        expect { run }.not_to change(PaymentCheckout, :count) # recorded: not asked again
        expect(adapter).to have_received(:checkout_status).once
      end
    end

    it "is recorded open after voiding the rental's other open checkout, and the run goes on to the next rental" do
      allow(adapter).to receive(:checkout_status).with(gid).and_return(:open)
      stray = PaymentCheckout.create!(reference: rental, provider: "shopify", provider_id: "gid://shopify/DraftOrder/35")
      later = create(:locker_rental, :active).tap { |r| r.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/36") }
      allow(adapter).to receive(:checkout_status).with("gid://shopify/DraftOrder/36").and_return(:paid)

      expect { run }.not_to raise_error
      expect(PaymentCheckout.where(reference: rental).order(:id).pluck(:provider_id, :status))
        .to eq([[stray.provider_id, "void"], [gid, "open"]])
      expect(PaymentCheckout.where(reference: later).pluck(:status)).to eq(%w[paid])
      expect(reported).to eq("open_checkout_not_stored" => [stray.id])
    end

    it "is reported, and not recorded, when Shopify's answer is unclear" do
      allow(adapter).to receive(:checkout_status).with(gid).and_return(:unknown)
      cancelled = create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }
      cancelled.update_columns(shopify_draft_order_id: "gid://shopify/DraftOrder/31", owned_until: nil)
      allow(adapter).to receive(:checkout_status).with("gid://shopify/DraftOrder/31").and_return(:paid)
      rental
      run
      expect(reported).to eq("checkout_status_unclear" => [rental.id])
      expect(PaymentCheckout.where(reference: rental)).to be_empty
      expect(PaymentCheckout.where(reference: cancelled).pluck(:status, :term)).to eq([["paid", nil]])
    end

    it "is left for the next run when the rental changed after it was listed" do
      allow(adapter).to receive(:checkout_status).with(gid) do
        LockerRental.where(id: rental.id).update_all(shopify_draft_order_id: nil)
        :paid
      end
      rental
      expect(run).to be_empty
      expect(PaymentCheckout.count).to eq(0)
    end

    it "is left alone when the rental is gone after it was listed" do
      allow(adapter).to receive(:checkout_status).with(gid) do
        LockerRental.where(id: rental.id).delete_all
        :paid
      end
      rental
      expect(run).to be_empty
      expect(PaymentCheckout.count).to eq(0)
    end

    it "is reported when its checkout cannot be recorded" do
      allow(adapter).to receive(:checkout_status).with(gid) do
        PaymentCheckout.create!(reference: create(:locker_rental), provider: "shopify", provider_id: gid, status: :void)
        :paid
      end
      rental
      run
      expect(reported).to include("checkout_status_unclear" => [rental.id])
    end

    it "fails the run on a Shopify error only after the differences were reported" do
      allow(adapter).to receive(:checkout_status).with(gid).and_raise(Timeout::Error)
      missing = create(:locker_rental, :await_payment).tap { |r| r.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/34") }
      rental
      expect { run }.to raise_error(Timeout::Error)
      expect(reported).to eq("checkout_missing" => [missing.id])
      expect(PaymentCheckout.where(reference: rental)).to be_empty
    end

    it "is never asked of Shopify for a rental awaiting payment, or active with a paid_at" do
      create(:locker_rental, :await_payment).update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/32")
      create(:locker_rental, :active, paid_at: 1.day.ago).update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/33")
      run
      expect(reported.keys).to eq(%w[checkout_missing])
    end
  end
end
