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
       { renter_ineligible: "renter_ineligible", rental_cancelled: "rental_cancelled", not_activatable: "not_activatable" },
       validate: { allow_nil: true }

  # What staff may resolve a held payment as.
  RESOLUTIONS = %w[refunded dismissed].freeze

  # Raised only to be reported (Rails.error.report): a paid order was recorded but not applied.
  class Held < StandardError; end

  # Staff apply a held payment to an ACTIVE rental whose renter is eligible again (reactivated after the
  # payment was held). Same conditional UPDATE as #resolve!, so it cannot race a refund or a settlement, and
  # the rental is locked and the renter read FOR SHARE (LockerRental#renter_eligible?) in the same transaction.
  # Not for a payment held because the rental was cancelled. Returns whether it was applied.
  def apply!(by:, note: nil)
    return false unless LockerRental::SETTLEABLE_HOLD_REASONS.include?(hold_reason)

    LockerRental.transaction do
      locker_rental.lock!
      locker_rental.active? && locker_rental.renter_eligible? && mark_applied!(by: by, note: note)
    end
  end

  # Held -> applied, as one conditional UPDATE. Also moves the rental's display-only paid_at. Call in a
  # transaction that holds the rental lock.
  def mark_applied!(by:, note: nil)
    now = Time.current
    changed = self.class.held.where(id: id).update_all(
      status: "applied", resolved_at: now, resolved_by_id: by&.id, resolution_note: note.presence, updated_at: now
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
      status: resolution.to_s, resolved_at: now, resolved_by_id: by.id, resolution_note: note.presence, updated_at: now
    )
    reload if changed == 1
    changed == 1
  end
end
