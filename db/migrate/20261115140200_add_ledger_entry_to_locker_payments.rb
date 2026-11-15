# frozen_string_literal: true

# A locker payment points at its ledger entry, and records when it was reversed. Both start empty; the
# existing columns and the hold-reason check are unchanged. down refuses while either holds a value.
class AddLedgerEntryToLockerPayments < ActiveRecord::Migration[8.1]
  def up
    add_reference :locker_payments, :ledger_entry, foreign_key: { to_table: :payment_ledger_entries },
                                                   index: { unique: true }
    add_column :locker_payments, :reversed_at, :datetime
  end

  # Refuses while any locker payment has a link or a reversal time: the backfill's own links are cleared by its down
  # first, so any left were written after deploy, and dropping the columns would lose them.
  def down
    filled = select_value("SELECT COUNT(*) FROM locker_payments WHERE ledger_entry_id IS NOT NULL OR reversed_at IS NOT NULL").to_i
    raise "#{filled} locker payments have a ledger entry or a reversal time; nothing was changed" if filled.positive?

    remove_column :locker_payments, :reversed_at
    remove_reference :locker_payments, :ledger_entry, foreign_key: { to_table: :payment_ledger_entries }, index: { unique: true }
  end
end
