# frozen_string_literal: true

# Finds stored orders nothing is working on any more and queues them again: a job lost from the queue (a failed
# enqueue, a worker killed hard) or a failed-state write that raised. Runs every SWEEP_INTERVAL (config/recurring.yml).
#
# Whether a job is still pending is not read from Solid Queue's tables (that ties this to its internals, and they
# live in another database). It is inferred from the row: a received order is waiting for its next retry until
# updated_at + the wait of its attempts (ApplyProcessedOrderJob.wait_for), so it is stranded only a grace period
# after that. Queueing it again is harmless: the job is idempotent (row lock, applied check).
#
# An order untouched for STRANDED_AFTER is reported (StrandedOrder, ids only), once per hour: a sweep run reports
# the orders whose age since their last update lies in [STRANDED_AFTER + k hours, + one sweep interval), so
# consecutive runs report an order once per hour with no column to remember it. Queueing again never touches the
# row (only an attempt does), so the age keeps growing while nothing works on it.
class SweepStrandedOrdersJob < ApplicationJob
  queue_as :default

  class StrandedOrder < StandardError; end

  SWEEP_INTERVAL = 10.minutes
  GRACE = 15.minutes
  STRANDED_AFTER = 2.hours

  def perform(now: Time.current)
    ProcessedOrder.where(status: "received").where("updated_at < ?", now - GRACE).find_each do |order|
      age = now - order.updated_at
      requeue(order) if age >= next_retry_due(order)
      report(order, age) if age >= STRANDED_AFTER.to_f && (age - STRANDED_AFTER.to_f) % 1.hour.to_f < SWEEP_INTERVAL.to_f
    end
  end

  private

  # Seconds after its last update that the order's retry is overdue by more than the grace period.
  def next_retry_due(order)
    ApplyProcessedOrderJob.wait_for([order.attempts, ApplyProcessedOrderJob::ATTEMPTS - 1].min).to_f + GRACE.to_f
  end

  def requeue(order)
    ApplyProcessedOrderJob.perform_later(order.id)
  end

  def report(order, age)
    Rails.error.report(
      StrandedOrder.new("order #{order.provider_ref} has been received for #{(age / 1.hour).floor} hours and is not applied"),
      handled: true, severity: :error,
      context: { shopify_order_id: order.provider_ref, attempts: order.attempts, status: order.status }
    )
  end
end
