# frozen_string_literal: true

namespace :job_orders do
  desc "Settle the Shopify draft of every job order that is not payable (one-off, idempotent; rerun until nothing is unresolved; exits 1 while any is)"
  task retire_stale_drafts: :environment do
    # Rows written before status transitions and deletes settled drafts: the same rule as a transition into the
    # order's current status, or a delete for a soft-deleted order (JobOrder#retire_stale_draft! ->
    # #settle_draft_order!): a COMPLETED draft is kept, an open one deleted, a vanished one cleared. Orders waiting
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
end
