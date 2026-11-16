# frozen_string_literal: true

class Membership
  # The record of one extra duplicate pending membership closed by Membership#close_as_duplicate_of: which row was
  # marked failed, the row kept for the same member and tier, the Shopify draft that was closed, the row's status and
  # last update before the change, and its last update right after it (marked_updated_at), so the change can be traced
  # and put back. restored_at is set once #restore has put the row back. The membership ids carry no foreign key: the
  # record is kept when a membership is deleted with its user, and #restore then reports the row gone.
  class DuplicateClosure < ApplicationRecord
    self.table_name = 'membership_duplicate_closures'

    belongs_to :membership, optional: true
    belongs_to :kept_membership, class_name: 'Membership', optional: true

    # The unique index on pending memberships (migration AddUniqueIndexToPendingMemberships). Once it is built, a closed
    # row cannot be put back beside the kept one.
    PENDING_UNIQUE_INDEX = 'index_memberships_on_pending_user_and_tier'

    scope :unrestored, -> { where(restored_at: nil) }

    # Puts the membership back as it was before it was closed: its status and updated_at (its draft id was never
    # changed), so it is exactly as it would have been without the closure, including for Membership::Expiry (a
    # restored row that is stale is expired by its next run). The Shopify draft stays deleted; the next checkout for
    # the row makes a new one. Under the member's row lock, the lock Membership.claim_pending takes, so a checkout
    # running at the same time cannot slip a pending row in between the check and the update. Returns :restored,
    # :changed (the row is not as the closure left it), :blocked (another pending membership holds the member and
    # tier and the unique index allows only one), :gone (the membership no longer exists) or :already (restored
    # before); every outcome but :restored changes nothing.
    def restore
      return restorable_state unless membership

      User.find(membership.user_id).with_lock do
        state = restorable_state
        next state unless state == :restorable

        next :changed unless untouched_since_closure.update_all(status: previous_status, updated_at: previous_updated_at) == 1

        update!(restored_at: Time.current)
        :restored
      end
    end

    # What #restore would do now, without changing anything: :restorable, :changed, :blocked, :gone or :already.
    def restorable_state
      return :already if restored_at
      return :gone unless membership
      return :changed unless untouched_since_closure.exists?
      return :blocked if pending_slot_taken?

      :restorable
    end

    private

    def pending_slot_taken?
      Membership.connection.index_name_exists?(:memberships, PENDING_UNIQUE_INDEX) &&
        Membership.pending.exists?(['(user_id, membership_tier_id) = (SELECT user_id, membership_tier_id FROM memberships WHERE id = ?)',
                                    membership_id])
    end

    def untouched_since_closure
      Membership.where(id: membership_id, status: 'failed', shopify_draft_order_id: shopify_draft_order_id, updated_at: marked_updated_at)
    end
  end
end
