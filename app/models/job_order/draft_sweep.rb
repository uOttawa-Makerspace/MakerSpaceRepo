# frozen_string_literal: true

# Reclaims the Shopify drafts no job order points at (the rules are in ShopifyDraftSweep).
#
# Every job-order draft carries a marker naming its order (Payments::ShopifyAdapter::MARKERS: the environment's
# operating tag, e.g. "makerepo_job_order", plus "job_order:<id>"). A job-order draft is only created inside the order's
# own locked operation, so there is no wait before the sweep may take one. Per draft, in ONE locked operation
# (JobOrder.reconcile_orphan_draft!): the order is re-read and kept when the database backs it (JobOrder#backs_draft?:
# a live order waiting for payment whose stored shopify_draft_order_id is this draft), otherwise the draft is fetched
# and deleted (never when Shopify reports it paid) and the stored id cleared. Deciding and deleting under one lock is
# what keeps a live invoice: a transition into COMPLETED keeps the order's stored id, so a draft that was an orphan a
# moment ago can become the invoice, and only the lock orders that against the delete. An order whose row is gone has
# no lock to take: JobOrder.reconcile_orphan_draft! settles its draft the same way (marker re-checked, unless paid).
# Run by `rake job_orders:sweep_orphan_drafts` and, regularly, by JobOrderDraftSweepJob (config/recurring.yml).
class JobOrder
  class DraftSweep < ShopifyDraftSweep
    SUMMARY_MESSAGE = "job order draft sweep: unresolved drafts"
    LOCK_KEY = Zlib.crc32("JobOrder::DraftSweep")

    private

    def model = JobOrder

    def record_label = "job order"

    def record_id_key = :job_order_id

    # looked up once, first: a missing Completed row fails here, at one defined point, and #run reports it as a
    # run-level abort (not once per draft)
    def preflight = JobStatus.completed.id

    def rerun_options(cap) = "rake CONFIRM_MAX_DELETES=#{cap}, or JobOrder::DraftSweep.run(max_deletes: #{cap})"

    def reconcile_draft(order_id, gid, may_delete:, context:)
      JobOrder.reconcile_orphan_draft!(order_id, gid, may_delete: may_delete, completed_id: context)
    end

    # The drafts the database does not back, counted with one query that reads what JobOrder.backs_draft? needs for
    # all the orders.
    def orphan_count(drafts, completed_id)
      rows = backing_rows(drafts.map(&:last))
      drafts.count { |gid, order_id| !(rows[order_id] && JobOrder.backs_draft?(gid, completed_id: completed_id, **rows[order_id])) }
    end

    # order id => the plain values JobOrder.backs_draft? decides on, for all the orders in ONE query (the latest status
    # is JobOrder::LATEST_STATUS_ID_SQL, the one definition the instance path uses too).
    def backing_rows(order_ids)
      JobOrder.where(id: order_ids.uniq).pluck(:id, :is_deleted, :shopify_draft_order_id, Arel.sql(JobOrder::LATEST_STATUS_ID_SQL))
              .to_h { |id, deleted, stored, status_id| [id, { deleted: deleted, stored_gid: stored, status_id: status_id }] }
    end
  end
end
