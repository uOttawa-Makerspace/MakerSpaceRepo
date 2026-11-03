# frozen_string_literal: true

# Applies one stored order (ProcessedOrder) with ShopOrderApplier: one run, one attempt. It is queued only by
# ProcessedOrder.dispatch_due, which owns the schedule. A run that fails has rolled its whole application back;
# the failure is then recorded on the row (error, attempts, the backoff until the next attempt, failed after
# ProcessedOrder::MAX_ATTEMPTS) and the error is not raised: the row, not this job, retries. Every error is
# retried because the stored payload loses nothing by waiting; staff re-run a failed order with
# `rake shop_orders:reapply`.
class ApplyProcessedOrderJob < ApplicationJob
  queue_as :default

  # Raised only to be reported (Rails.error.report).
  class OrderApplyFailed < StandardError; end
  class OrderApplyRetrying < StandardError; end

  def perform(processed_order_id)
    order = ProcessedOrder.find_by(id: processed_order_id)
    return unless order&.status == "received"

    ShopOrderApplier.new(order).call
  rescue StandardError => e
    ProcessedOrder.record_failure!(processed_order_id, e)
  end
end
