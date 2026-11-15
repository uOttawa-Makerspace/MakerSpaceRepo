# frozen_string_literal: true

# A locker payment points at its ledger entry, and records when it was reversed. Both start empty; the
# existing columns and the hold-reason check are unchanged.
class AddLedgerEntryToLockerPayments < ActiveRecord::Migration[8.1]
  def change
    add_reference :locker_payments, :ledger_entry, foreign_key: { to_table: :payment_ledger_entries },
                                                   index: { unique: true }
    add_column :locker_payments, :reversed_at, :datetime
  end
end
