# frozen_string_literal: true

# Applies one stored order (ProcessedOrder) with ShopOrderApplier. Every error is retried, with a growing wait
# (10 attempts over about a day and a half, see wait_for), because the stored payload loses nothing by waiting. A failed
# attempt rolls its whole application back, then counts itself and keeps its error on the row in a transaction of
# its own. When the attempts run out the order is marked failed and reported; staff re-run it with
# `rake shop_orders:reapply`.
class ApplyProcessedOrderJob < ApplicationJob
  queue_as :default

  class OrderApplyFailed < StandardError; end

  ATTEMPTS = 10

  # The wait before retry number `executions` (1..9): 61s, 92s, 5m, 18m, 53m, 2h10m, 4h41m, 9h07m, 16h25m.
  def self.wait_for(executions) = (executions**5 + 60).seconds

  retry_on StandardError, attempts: ATTEMPTS, wait: ->(executions) { wait_for(executions) } do |job, error|
    ProcessedOrder.mark_failed!(job.arguments.first, error)
  end

  def perform(processed_order_id)
    ShopOrderApplier.new(ProcessedOrder.find(processed_order_id)).call
  rescue StandardError => e
    ProcessedOrder.record_failure!(processed_order_id, e)
    raise
  end
end
