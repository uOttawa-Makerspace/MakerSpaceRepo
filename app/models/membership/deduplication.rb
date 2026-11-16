# frozen_string_literal: true

class Membership
  # Older data can hold more than one pending membership for a member and tier: one open checkout per pair was not
  # enforced by the database. Merging two accounts (rake users:merge_duplicates) meets the same case across users: the
  # kept account's row checkout serves is kept and the other account's pending row for that tier is closed the same
  # way. Of each such pair the row checkout serves is kept (Membership.served_pending: its draft
  # is the link the member holds). Each other one has its Shopify draft closed and is then marked failed, and a
  # Membership::DuplicateClosure row records what it was, so the change can be traced and put back
  # (Membership::DuplicateClosure#restore). No row is deleted.
  #
  # A draft that is paid is never closed and its membership is never marked: the payment is applied to it as usual.
  # A draft any other membership row also holds (the kept row or any other) is never closed either. The mark is a conditional UPDATE from the state this run
  # saw (Membership#change_if_pending) and its record is written in the same transaction, so two runs, or a member who
  # buys again meanwhile, cannot both change a row. Shopify's draft delete is idempotent (a second delete only reports
  # the draft gone), so a run can be repeated.
  module Deduplication
    extend ActiveSupport::Concern

    class_methods do
      # Member and tier pairs that have more than one pending membership, as [user_id, tier_id, [membership ids]],
      # ordered by member, then tier, with the ids ascending. Reads only.
      def pending_duplicates
        pending.group(:user_id, :membership_tier_id).having('count(*) > 1').order(:user_id, :membership_tier_id)
               .pluck(:user_id, :membership_tier_id, Arel.sql('array_agg(id ORDER BY id)'))
      end

      # The pending memberships of `other_user` for a tier `user` also has a pending membership for, by id: the rows a
      # merge of `other_user` into `user` closes (each with #close_as_duplicate_of, in favour of `user`'s served row).
      def pending_conflicts(user, other_user)
        pending.where(user_id: other_user.id, membership_tier_id: pending.where(user_id: user.id).select(:membership_tier_id)).order(:id)
      end
    end

    # Closes this extra pending membership in favour of `kept`, the row checkout serves for the same tier. Both rows
    # must belong to `allowed_user_ids`: by default this row's own member; a merge passes the two accounts it merges.
    # Returns :closed (draft closed, row marked failed and recorded), :paid (the draft is paid: nothing changed),
    # :open (Shopify kept the draft payable: the row stays pending) or :changed (the row is left as it is: `kept` is no
    # longer the row checkout serves, this row changed, or another membership holds its draft). Shopify errors raise.
    def close_as_duplicate_of(kept, allowed_user_ids: [user_id])
      return :changed unless duplicate_of?(kept, allowed_user_ids)

      gid = shopify_draft_order_id
      seen = updated_at
      outcome = remove_stale_draft(gid)
      return outcome unless outcome == :removed

      mark_failed_as_duplicate(kept, gid, seen) ? :closed : :changed
    end

    private

    def duplicate_of?(kept, allowed_user_ids)
      closable_for?(kept, allowed_user_ids) && kept_served?(kept) && unchanged_pending? && !draft_shared?
    end

    # Another row of the same tier, and both rows belong to the accounts allowed.
    def closable_for?(kept, allowed_user_ids)
      kept.id != id && kept.membership_tier_id == membership_tier_id && ([kept.user_id, user_id] - allowed_user_ids).empty?
    end

    def kept_served?(kept)
      self.class.served_pending(kept.user_id, kept.membership_tier_id)&.id == kept.id
    end

    def unchanged_pending?
      self.class.pending.exists?(id: id, shopify_draft_order_id: shopify_draft_order_id, updated_at: updated_at)
    end

    # Another membership row (of any member, the kept row included) points at this row's draft: closing the draft
    # would take away that row's link.
    def draft_shared?
      shopify_draft_order_id.present? && self.class.where(shopify_draft_order_id: shopify_draft_order_id).where.not(id: id).exists?
    end

    def mark_failed_as_duplicate(kept, gid, seen)
      self.class.transaction do
        next false unless change_if_pending({ shopify_draft_order_id: gid, updated_at: seen }, status: 'failed')

        DuplicateClosure.create!(membership_id: id, kept_membership_id: kept.id, shopify_draft_order_id: gid,
                                 previous_status: 'pending', previous_updated_at: seen,
                                 marked_updated_at: self.class.where(id: id).pick(:updated_at))
        true
      end
    end
  end
end
