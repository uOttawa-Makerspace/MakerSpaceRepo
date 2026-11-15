# frozen_string_literal: true

# One Shopify order that paid a locker rental. Immutable fact: only its status moves
# (applied | held | refunded | dismissed). A held payment is one that could not be applied to the
# rental (see HOLD_REASONS); it stays held until staff settle it (the rental is assigned active, or
# they mark it refunded or dismissed). Never deleted. Created only through LockerRental#record_payment.
# Each one also has a payment entry in the payments ledger (ledger_entry), and a refunded one a reversal entry
# (reversed_at), written beside these columns, which stay what every decision reads.
class LockerPayment < ApplicationRecord
  belongs_to :locker_rental
  belongs_to :resolved_by, class_name: "User", optional: true
  belongs_to :ledger_entry, class_name: "PaymentLedgerEntry", optional: true

  enum :status,
       { applied: "applied", held: "held", refunded: "refunded", dismissed: "dismissed" },
       validate: true
  enum :hold_reason,
       { renter_ineligible: "renter_ineligible", rental_cancelled: "rental_cancelled", not_activatable: "not_activatable",
         # a second payment for a rental that is already active and paid: a duplicate charge, to refund
         already_paid: "already_paid" },
       validate: { allow_nil: true }

  NOTE_MAX_LENGTH = 500
  MONEY_MAX = BigDecimal("99999999.99") # precision 10, scale 2

  # A Shopify money string/number as a BigDecimal with 2 decimals; nil when blank. Raises ArgumentError for
  # anything malformed, negative or out of range for the column, so the caller can store nil and report it.
  def self.money(value)
    return nil if value.blank?

    amount = BigDecimal(value.to_s.strip, exception: false)
    raise ArgumentError, "malformed amount" if amount.nil? || !amount.finite?
    raise ArgumentError, "amount out of range" if amount.negative? || amount.round(2) > MONEY_MAX

    amount.round(2)
  end

  # What staff may resolve a held payment as.
  RESOLUTIONS = %w[refunded dismissed].freeze

  # Raised only to be reported (Rails.error.report): a paid order was recorded but not applied.
  class Held < StandardError; end
  # Raised only to be reported: a figure of a paid order was malformed or out of range and was stored as nil.
  class MalformedPaymentAmount < StandardError; end

  # Held -> applied, as one conditional UPDATE, only by LockerRental#settle_held_payments! (assigning the rental
  # active). Staff cannot apply a payment by hand: on an active rental a held payment is a duplicate (refund it)
  # or one that arrived after the assignment (dismiss it with a note). Also moves the rental's display-only
  # paid_at. Call in a transaction that holds the rental lock.
  def mark_applied!(by:)
    now = Time.current
    changed = self.class.held.where(id: id).update_all(
      status: "applied", resolved_at: now, resolved_by_id: by&.id, updated_at: now
    )
    return false unless changed == 1

    reload
    locker_rental.stamp_paid_at(paid_at)
    locker_rental.record_checkout_paid
    true
  end

  # Staff decision on a held payment. One conditional UPDATE, so it cannot race with the payment being
  # settled by an assignment (whichever commits first wins, the other returns false). A refund also sets
  # reversed_at and writes the reversal of the payment's ledger entry, in the same transaction.
  def resolve!(resolution, by:, note: nil)
    raise ArgumentError, "unknown resolution #{resolution.inspect}" unless RESOLUTIONS.include?(resolution.to_s)

    transaction do
      changed = self.class.held.where(id: id).update_all(resolution_columns(resolution.to_s, by, note)) == 1
      reload if changed
      record_reversal_in_ledger if changed && refunded?
      changed
    end
  end

  # This payment's entry in the payments ledger, written and linked (ledger_entry_id) the first time. Safe to call
  # again, and never raises on a row already there: the entry is written with ON CONFLICT DO NOTHING
  # (PaymentLedgerEntry.record_payment), and linked only while this payment has no entry and no other payment has
  # that one. nil when it could not be linked; LockerRental::PaymentRecordsCheck reports the payment then.
  def record_in_ledger
    return ledger_entry if ledger_entry_id

    entry = PaymentLedgerEntry.record_payment(
      provider: Payments::ShopifyAdapter::PROVIDER, provider_ref: shopify_order_id, amount: amount
    )
    entry if entry && link_ledger_entry(entry)
  end

  private

  def resolution_columns(resolution, by, note)
    now = Time.current
    columns = { status: resolution, resolved_at: now, resolved_by_id: by.id, updated_at: now,
                resolution_note: note.to_s.delete("\u0000").strip.first(NOTE_MAX_LENGTH).presence }
    resolution == "refunded" ? columns.merge(reversed_at: now) : columns
  end

  def link_ledger_entry(entry)
    linked = self.class.where(id: id, ledger_entry_id: nil)
                 .where("NOT EXISTS (SELECT 1 FROM locker_payments other WHERE other.ledger_entry_id = ?)", entry.id)
                 .update_all(ledger_entry_id: entry.id) == 1
    @attributes.write_from_database("ledger_entry_id", entry.id) if linked
    linked
  end

  def record_reversal_in_ledger
    entry = record_in_ledger
    PaymentLedgerEntry.record_reversal(entry) if entry
  end
end
