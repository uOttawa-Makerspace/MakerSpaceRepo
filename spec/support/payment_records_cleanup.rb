# frozen_string_literal: true

# For non-transactional examples: removes the committed locker payments of the given rentals with what is written
# beside them, their payments ledger entries (the append-only trigger is switched off inside this one transaction)
# and the rentals' payment checkout records.
module PaymentRecordsCleanup
  LEDGER_TRIGGER = "payment_ledger_entries_no_change"

  def delete_locker_payment_records(rental_ids)
    ActiveRecord::Base.transaction do
      payments = LockerPayment.where(locker_rental_id: rental_ids)
      entry_ids = payments.where.not(ledger_entry_id: nil).pluck(:ledger_entry_id)
      payments.delete_all
      delete_ledger_entries(entry_ids)
      PaymentCheckout.where(reference_type: "LockerRental", reference_id: rental_ids).delete_all
    end
  end

  private

  def delete_ledger_entries(entry_ids)
    connection = ActiveRecord::Base.connection
    connection.execute("ALTER TABLE payment_ledger_entries DISABLE TRIGGER #{LEDGER_TRIGGER}")
    PaymentLedgerEntry.where(reversed_entry_id: entry_ids).delete_all
    PaymentLedgerEntry.where(id: entry_ids).delete_all
    connection.execute("ALTER TABLE payment_ledger_entries ENABLE TRIGGER #{LEDGER_TRIGGER}")
  end
end

RSpec.configure do |config|
  config.include PaymentRecordsCleanup
end
