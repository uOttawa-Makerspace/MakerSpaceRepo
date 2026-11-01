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
