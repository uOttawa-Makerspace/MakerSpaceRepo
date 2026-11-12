# frozen_string_literal: true

# Reclaims the Shopify drafts no locker rental points at (the rules are in ShopifyDraftSweep).
#
# A locker draft is created on Shopify outside any lock and stored afterwards (LockerRental#checkout_link), so a
# crash between the two, or a checkout that is abandoned, leaves a payable draft no rental points at. Every locker draft
# carries a marker naming its rental (LockerRental#shopify_draft_order_tags: the environment's operating tag,
# e.g. "makerepo_locker", plus "locker_rental:<id>"). Per draft, in ONE locked operation
# (LockerRental.reconcile_orphan_draft!): the rental is kept as it is, and the draft is fetched and deleted (never when
# Shopify reports it paid) unless the rental is waiting for payment and stores this draft. A draft younger than MIN_AGE is
# left alone: its creator may still be about to store it.
# Run regularly by JobOrderDraftSweepJob (config/recurring.yml).
class LockerRental
  class DraftSweep < ShopifyDraftSweep
    SUMMARY_MESSAGE = "locker draft sweep: unresolved drafts"
    LOCK_KEY = Zlib.crc32("LockerRental::DraftSweep")
    MIN_AGE = 1.hour

    private

    def model = LockerRental

    def record_label = "locker rental"

    def record_id_key = :locker_rental_id

    def min_age = MIN_AGE

    def reconcile_draft(rental_id, gid, may_delete:, context:)
      LockerRental.reconcile_orphan_draft!(rental_id, gid, may_delete: may_delete)
    end

    # The drafts the database does not back, counted with one query over all the rentals.
    def orphan_count(drafts, _context)
      rows = LockerRental.where(id: drafts.map(&:last).uniq).pluck(:id, :state, :shopify_draft_order_id).to_h { |id, state, stored| [id, [state, stored]] }
      drafts.count { |gid, rental_id| !(rows[rental_id] && LockerRental.backs_draft?(gid, state: rows[rental_id][0], stored_gid: rows[rental_id][1])) }
    end
  end
end
