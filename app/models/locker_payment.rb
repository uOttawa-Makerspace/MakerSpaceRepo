# frozen_string_literal: true

# One Shopify order that paid a locker rental. Immutable fact: only its status moves
# (applied | held | refunded | dismissed). A held payment is one that could not be applied to the
# rental (see HOLD_REASONS); it stays held until staff settle it (the rental is assigned active, or
# they mark it refunded or dismissed). Never deleted. Created only through LockerRental#record_payment.
class LockerPayment < ApplicationRecord
  belongs_to :locker_rental
  belongs_to :resolved_by, class_name: "User", optional: true

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
    true
  end

  # Staff decision on a held payment. One conditional UPDATE, so it cannot race with the payment being
  # settled by an assignment (whichever commits first wins, the other returns false).
  def resolve!(resolution, by:, note: nil)
    raise ArgumentError, "unknown resolution #{resolution.inspect}" unless RESOLUTIONS.include?(resolution.to_s)

    now = Time.current
    changed = self.class.held.where(id: id).update_all(
      status: resolution.to_s, resolved_at: now, resolved_by_id: by.id, resolution_note: note.to_s.delete("\u0000").strip.first(NOTE_MAX_LENGTH).presence, updated_at: now
    )
    reload if changed == 1
    changed == 1
  end
end
