# frozen_string_literal: true

# One-off clean-up of the locker drafts made before locker drafts carried a rental marker: open drafts with this
# environment's locker tag, no locker_rental marker, and that no rental stores. Run by `rake lockers:untagged_drafts`,
# which only lists them; `rake lockers:untagged_drafts[apply]` closes them after the list has been approved.
#
# It is the ShopifyDraftSweep (listing, kill switch, fail-closed reporting, advisory lock) with a different rule for
# what is listed and what is kept: a draft any rental stores, in any state, is kept (checked again inside the
# transaction that deletes); a draft younger than MIN_AGE is left alone (during a rollout the previous code may still be
# creating unmarked drafts whose rental has not stored them yet); a paid draft is never touched (it is not listed, and is
# checked again when fetched); a draft with a marker is left to LockerRental::DraftSweep.
# No rental row is changed. A draft Shopify no longer has counts as cleared, so a second run changes nothing.
class LockerRental
  class UntaggedDraftSweep < ShopifyDraftSweep
    SUMMARY_MESSAGE = "locker untagged draft sweep: unresolved drafts"
    LOCK_KEY = Zlib.crc32("LockerRental::UntaggedDraftSweep")
    OUTCOMES = %i[kept deleted cleared unmarked listed].freeze
    MIN_AGE = 24.hours

    # The gids a dry run listed (what an apply run would close), and the gids an apply run closed (the audit trail).
    attr_reader :listed, :closed

    # A dry run (the default) lists and changes nothing, and has no cap: it is only a list.
    def self.run(apply: false, max_deletes: MAX_DELETES)
      sweep = new(apply: apply, max_deletes: apply ? max_deletes : Float::INFINITY)
      [sweep.run, sweep]
    end

    def initialize(apply: false, max_deletes: MAX_DELETES)
      super(max_deletes: max_deletes)
      @apply = apply
      @listed = []
      @closed = []
    end

    private

    def model = LockerRental

    def record_label = "locker draft"

    def record_id_key = :draft_order_id

    def min_age = MIN_AGE

    # [gid, gid] for a payable draft of this environment with no locker marker at all (the record id is the gid).
    def marked(node)
      return nil unless Payments::ShopifyAdapter::DraftRemoval::PAYABLE_STATUSES.include?(node["status"]) && unmarked_here?(node["tags"])
      return nil unless old_enough?(node)

      [node["id"], node["id"]] if node["id"].present?
    end

    # This environment's locker draft with no locker marker at all.
    def unmarked_here?(tags)
      model.draft_order_processable?(tags) && model.draft_tag_list(tags).none? { |t| t.start_with?("#{model.draft_marker_name}:") }
    end

    def orphan_count(drafts, _context)
      stored = LockerRental.where(shopify_draft_order_id: drafts.map(&:first)).pluck(:shopify_draft_order_id)
      drafts.count { |gid, _| stored.exclude?(gid) }
    end

    def reconcile_draft(gid, _gid, may_delete:, context:)
      return dry_run_listing(gid) unless @apply

      ApplicationRecord.own_transaction("LockerRental::UntaggedDraftSweep") { close_unless_stored(gid, may_delete) }
    rescue ActiveRecord::LockWaitTimeout => e
      Outcome.refused(:busy, e)
    rescue ActiveRecord::Deadlocked => e
      Outcome.refused(:deadlock, e)
    rescue LockerRental::OrphanDraftRefused => e
      Outcome.refused(:draft_not_voidable, e)
    end

    # Decided and deleted in one transaction: a rental that stores the draft is locked (and keeps it), and the check is
    # made again right before the delete.
    def close_unless_stored(gid, may_delete)
      return Outcome.done(:kept) if LockerRental.lock.exists?(shopify_draft_order_id: gid)
      return Outcome.refused(:delete_cap) unless may_delete

      outcome = LockerRental.settle_orphan_draft(gid, "the draft order is not an unmarked draft of this environment") { |tags| unmarked_here?(tags) }
      @closed << gid if %i[deleted cleared].include?(outcome)
      Outcome.done(outcome)
    end

    def dry_run_listing(gid)
      return Outcome.done(:kept) if LockerRental.exists?(shopify_draft_order_id: gid)

      @listed << gid
      Outcome.done(:listed)
    end
  end
end
