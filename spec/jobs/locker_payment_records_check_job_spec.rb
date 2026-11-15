# frozen_string_literal: true

require "rails_helper"

RSpec.describe LockerPaymentRecordsCheckJob, type: :job do
  it "reports a locker payment without a ledger entry, and changes nothing" do
    rental = create(:locker_rental, :active).tap { |r| r.update!(state: :cancelled) }
    payment = rental.record_payment(shopify_order_id: "9100")
    payment.update_column(:ledger_entry_id, nil)
    reports = []
    allow(Rails.error).to receive(:report) { |error, **opts| reports << [error.class, opts[:context]] }

    expect { described_class.perform_now }.not_to(change { [payment.reload.attributes, PaymentLedgerEntry.count] })
    expect(reports).to eq([[LockerRental::PaymentRecordsCheck::Difference,
                            { check: "ledger_entry_missing", count: 1, ids: [payment.id] }]])
  end
end
