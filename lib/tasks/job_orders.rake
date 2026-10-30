# frozen_string_literal: true

namespace :job_orders do
  desc "Settle the Shopify draft of every job order that is not payable (one-off, idempotent; rerun until nothing is unresolved; exits 1 while any is)"
  task retire_stale_drafts: :environment do
    # Rows written before status transitions and deletes settled drafts: the same rule as a transition into the
    # order's current status, or a delete for a soft-deleted order (JobOrder#retire_stale_draft! ->
    # #settle_draft_order!, the rule JobOrder.draft_settlement): a COMPLETED draft is kept, an open one deleted, a vanished one cleared. Orders waiting
    # for payment are left alone. Each order runs as one locked operation (JobOrder#locked_operation), so a refusal
    # (busy, deadlock, order gone, Shopify could not confirm) is a result, listed as unresolved. An unexpected
    # exception is reported and listed the same way: it must not abort the run for the orders after it.
    counts = Hash.new(0)
    unresolved = []
    JobOrder.where.not(shopify_draft_order_id: [nil, ""]).order(:id).pluck(:id).each do |id|
      result = JobOrder.retire_stale_draft!(id)
      if result.ok?
        counts[result.value] += 1
      else
        unresolved << id
        warn "job order ##{id} not resolved (#{result.reason}): #{result.error&.message}"
      end
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { job_order_id: id, where: "job_orders:retire_stale_drafts" })
      unresolved << id
      warn "job order ##{id} not resolved (unexpected): #{e.class}: #{e.message}"
    end
    %i[kept deleted cleared skipped].each { |outcome| puts "#{outcome}: #{counts[outcome]}" }
    puts "unresolved: #{unresolved.size}#{" (#{unresolved.join(', ')})" if unresolved.any?}"
    exit(1) if unresolved.any?
  end

  desc "Delete the Shopify drafts no job order points at (orphans of a rollback after a Shopify create); exits 1 while any is unresolved, 2 when skipped because another sweep is running; CONFIRM_MAX_DELETES=n lifts the cap of 200 orphans (over it nothing is deleted)"
  task sweep_orphan_drafts: :environment do
    # Shopify mutations cannot be rolled back: a database or lock error after a draft create leaves a payable draft
    # that no order row points at (JobOrder#locked_operation). Every job-order draft carries the tag
    # "job_order:<id>" beside the environment's operating tag, and JobOrder::DraftSweep reconciles this
    # environment's payable (OPEN, INVOICE_SENT) marked drafts against the database: kept only for a live COMPLETED order whose stored
    # draft id is this draft, else deleted (decided and deleted under the order's row lock) (never a COMPLETED/paid one; never a draft without the marker, e.g.
    # lockers, memberships, other environments). Fail closed: an error is listed as unresolved. Idempotent.
    # JobOrderDraftSweepJob runs the same code hourly (config/recurring.yml).
    # More orphans than the cap (200) delete NOTHING and exit 1: check the database, then CONFIRM_MAX_DELETES=<n>.
    cap = ENV["CONFIRM_MAX_DELETES"]
    abort "CONFIRM_MAX_DELETES must be a whole number" if cap && !cap.match?(/\A\d+\z/)
    report = cap ? JobOrder::DraftSweep.run(max_deletes: cap.to_i) : JobOrder::DraftSweep.run
    if report.skipped
      puts "skipped: another sweep is running"
      exit(2) # a skipped run did not sweep: not a success
    end
    report.counts.each { |outcome, n| puts "#{outcome}: #{n}" }
    report.unresolved.each { |line| warn "not resolved: #{line}" }
    puts "unresolved: #{report.unresolved.size}"
    exit(1) unless report.ok?
  end
end
