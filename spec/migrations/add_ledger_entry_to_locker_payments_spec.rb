# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261115140200_add_ledger_entry_to_locker_payments")

# DDL is transactional in the test database: each example takes the columns off first, and the rollback restores
# the real schema afterwards.
RSpec.describe AddLedgerEntryToLockerPayments do
  let(:connection) { ActiveRecord::Base.connection }
  let(:original) { %w[amount created_at currency hold_reason id locker_rental_id order_total paid_at resolution_note resolved_at resolved_by_id shopify_order_id status updated_at] }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    LockerPayment.reset_column_information
  end

  def columns = connection.columns(:locker_payments).map(&:name).sort

  def rows = connection.select_rows("SELECT #{original.join(', ')} FROM locker_payments ORDER BY id")

  before do
    create(:locker_payment, :held, amount: "25.00")
    create(:locker_payment, amount: "30.00")
    migrate(:down)
  end

  after { LockerPayment.reset_column_information }

  it "adds the two empty columns, keeping every row and the hold-reason check as they were" do
    before_rows = rows
    hold_check = connection.check_constraints(:locker_payments).find { |c| c.name == "locker_payments_hold_reason_check" }.expression

    migrate(:up)

    expect(columns).to eq((original + %w[ledger_entry_id reversed_at]).sort)
    expect(rows).to eq(before_rows)
    expect(connection.select_values("SELECT DISTINCT ledger_entry_id IS NULL AND reversed_at IS NULL FROM locker_payments")).to eq([true])
    expect(connection.check_constraints(:locker_payments).find { |c| c.name == "locker_payments_hold_reason_check" }.expression)
      .to eq(hold_check)
    expect(connection.foreign_keys(:locker_payments).map(&:to_table)).to include("payment_ledger_entries")
  end

  it "rolls back to the original columns with every row kept, and runs again" do
    migrate(:up)
    before_rows = rows
    migrate(:down)

    expect(columns).to eq(original.sort)
    expect(rows).to eq(before_rows)
    migrate(:up)
    expect(columns).to include("ledger_entry_id", "reversed_at")
  end
end
