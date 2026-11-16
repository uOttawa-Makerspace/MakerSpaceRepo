# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261115140400_backfill_payment_ledger_from_locker_payments")

# DDL is transactional in the test database: each example drops the record table first, and the rollback restores
# the real schema afterwards.
RSpec.describe BackfillPaymentLedgerFromLockerPayments do
  let(:connection) { ActiveRecord::Base.connection }
  let(:recorded) { Time.zone.parse("2026-11-02 09:00") }
  let(:refunded_at) { Time.zone.parse("2026-11-05 15:30") }
  let(:original) { %w[id amount currency hold_reason locker_rental_id order_total paid_at resolution_note resolved_at resolved_by_id shopify_order_id status created_at updated_at reversed_at] }

  before { connection.drop_table(described_class::TABLE) }

  # The migrator runs each migration in a transaction; a savepoint stands in for it, so a refused down is undone.
  def migrate(direction = :up)
    connection.transaction(requires_new: true) do
      ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    end
  end

  def payment(status, amount: "25.00", **attrs)
    record = create(:locker_payment, amount: amount, status: status, resolved_at: status == "held" ? nil : refunded_at,
                                     hold_reason: status == "held" ? "renter_ineligible" : nil, **attrs)
    record.update_columns(created_at: recorded)
    record
  end

  def entries
    PaymentLedgerEntry.includes(:reversed_entry).order(:id).map do |e|
      [e.provider, e.provider_ref, e.amount, e.kind, e.reversed_entry&.provider_ref, e.created_at]
    end
  end

  def payment_rows = connection.select_rows("SELECT #{original.join(', ')} FROM locker_payments ORDER BY id")

  def links = LockerPayment.order(:id).map { |p| p.ledger_entry_id && PaymentLedgerEntry.find(p.ledger_entry_id).provider_ref }

  it "writes a payment entry for every locker payment and a reversal for a refunded one, linking each payment" do
    applied = payment("applied", amount: "30.00")
    held = payment("held", amount: nil)
    refunded = payment("refunded")
    dismissed = payment("dismissed")
    before_rows = payment_rows

    migrate

    ids = [applied, held, refunded, dismissed].map(&:shopify_order_id)
    expect(entries).to eq([
      ["shopify", ids[0], BigDecimal("30.00"), "payment", nil, recorded],
      ["shopify", ids[1], nil, "payment", nil, recorded],
      ["shopify", ids[2], BigDecimal("25.00"), "payment", nil, recorded],
      ["shopify", ids[3], BigDecimal("25.00"), "payment", nil, recorded],
      ["shopify", ids[2], BigDecimal("25.00"), "reversal", ids[2], refunded_at]
    ])
    expect(links).to eq(ids)
    expect(payment_rows).to eq(before_rows)
  end

  it "writes nothing more when run again" do
    payment("applied")
    payment("refunded")
    migrate

    expect { migrate }.not_to(change { entries })
    expect(connection.select_value("SELECT COUNT(*) FROM #{described_class::TABLE}").to_i).to eq(3)
  end

  it "removes exactly the entries it wrote and clears the links on down, and runs again" do
    payment("applied")
    payment("refunded")
    before_rows = payment_rows
    migrate
    migrate(:down)

    expect(PaymentLedgerEntry.count).to eq(0)
    expect(links).to eq([nil, nil])
    expect(payment_rows).to eq(before_rows)
    expect(connection.table_exists?(described_class::TABLE)).to be(false)
    expect(connection.select_value(<<~SQL.squish)).to eq("O")
      SELECT tgenabled FROM pg_trigger WHERE tgname = '#{described_class::TRIGGER}'
    SQL

    migrate
    expect(PaymentLedgerEntry.count).to eq(3)
  end

  it "refuses down, changing nothing, when a link it wrote has changed since" do
    first = payment("applied")
    payment("applied")
    migrate
    first.update_columns(ledger_entry_id: nil)

    expect { migrate(:down) }.to raise_error(/cleared 1 of 2 links/)
    expect(PaymentLedgerEntry.count).to eq(2)
    expect(connection.table_exists?(described_class::TABLE)).to be(true)
  end

  it "refuses down when the record table is missing" do
    expect { migrate(:down) }.to raise_error(/payment_ledger_backfills is missing/)
  end
end
