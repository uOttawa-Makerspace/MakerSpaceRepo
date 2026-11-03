# frozen_string_literal: true

# Applies one stored order (ProcessedOrder) with ShopOrderApplier: one run, one attempt. It is queued only by
# ProcessedOrder.dispatch_due, which owns the schedule and passes the lease it took as the token. The run starts by
# counting its attempt against that token (ProcessedOrder.start_run!), which also gives the run a fresh lease of its
# own; a stale token, a duplicate job or an order already settled does nothing, and so does a start that times out
# waiting for another run that holds the order (nothing of ours failed). A run that fails has rolled its whole
# application back; the failure is then recorded on the row (error, the backoff until the next attempt, failed after
# ProcessedOrder::MAX_ATTEMPTS) and the error is not raised: the row, not this job, retries. Every error is retried
# because the stored payload loses nothing by waiting; staff re-run a failed order with `rake shop_orders:reapply`.
class ApplyProcessedOrderJob < ApplicationJob
  queue_as :default

  # Raised only to be reported (Rails.error.report).
  class OrderApplyFailed < StandardError; end
  class OrderApplyRetrying < StandardError; end
  class StaleRunFailed < StandardError; end
  class PostCommitSideEffectFailed < StandardError; end

  def perform(processed_order_id, token)
    started = begin
      ProcessedOrder.start_run!(processed_order_id, token)
    rescue ActiveRecord::LockWaitTimeout
      # Another run is applying this order: nothing of ours failed, and its outcome decides what happens next.
      Rails.logger.debug { "[ApplyProcessedOrderJob] order #{processed_order_id} is held by another run" }
      return
    end
    return unless started

    token = started.last # the run's own lease from now on

    order = ProcessedOrder.find_by(id: processed_order_id)
    return unless order&.status == "received"

    ShopOrderApplier.new(order).call
  rescue StandardError => e
    ProcessedOrder.record_failure!(processed_order_id, token, e)
  end
end
