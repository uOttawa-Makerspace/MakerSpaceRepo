# frozen_string_literal: true

namespace :job_orders do
  desc "Settle the Shopify draft of every job order whose status is not payable (one-off, idempotent; rerun until nothing is unresolved)"
  task retire_stale_drafts: :environment do
    # Rows written before status transitions settled drafts: the same rule as a transition into the order's
    # current status (JobOrder#settle_draft_order!): a COMPLETED draft is kept, an open one deleted, a vanished one
    # cleared. Orders waiting for payment are left alone. Each order runs under its own row lock.
    counts = Hash.new(0)
    unresolved = []
    JobOrder.where.not(shopify_draft_order_id: [nil, ""]).order(:id).pluck(:id).each do |id|
      counts[JobOrder.retire_stale_draft!(id)] += 1
    rescue JobOrder::StaleDraftOrderError, ActiveRecord::LockWaitTimeout => e
      unresolved << id
      warn "job order ##{id} not resolved: #{e.class}: #{e.message}"
    end
    %i[kept deleted cleared skipped].each { |outcome| puts "#{outcome}: #{counts[outcome]}" }
    puts "unresolved: #{unresolved.size}#{" (#{unresolved.join(', ')})" if unresolved.any?}"
  end
end
