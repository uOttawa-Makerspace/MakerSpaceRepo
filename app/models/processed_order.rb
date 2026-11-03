# frozen_string_literal: true

# The inbox of payment-provider orders (see CreateProcessedOrders): the webhook stores the verified body with
# `receive!` and answers, ApplyProcessedOrderJob applies it. The unique key (provider, provider_ref) means one row
# per unit of work: the provider order for orders/paid, and a separate "<id>/fulfilled" unit for the cash-locker
# orders/fulfilled delivery of the same order (see ref_for). `topic` records which delivery the row came from.
# status: received (still to apply), applied, or failed (retries exhausted; staff re-run it with
# shop_orders:reapply). Rows are never deleted.
class ProcessedOrder < ApplicationRecord
  STATUSES = %w[received applied failed].freeze

  scope :unapplied, -> { where.not(status: "applied") }

  def applied? = status == "applied"

  # The provider_ref of an order's delivery of `topic`.
  def self.ref_for(order_id, topic)
    topic == "orders/fulfilled" ? "#{order_id}/fulfilled" : order_id.to_s
  end

  # Stores the delivery with INSERT ... ON CONFLICT DO NOTHING and returns [row, inserted]: the new row, or the
  # row a first delivery stored (inserted false), whatever its status.
  def self.receive!(provider:, order_id:, topic:, payload:, name: nil)
    ref = ref_for(order_id, topic)
    now = Time.current
    inserted = insert_all(
      [{ provider: provider, provider_ref: ref, topic: topic, order_name: name.presence&.to_s&.first(64), payload: payload,
         created_at: now, updated_at: now }],
      unique_by: %i[provider provider_ref], returning: %w[id]
    ).rows.first
    return [find(inserted.first), true] if inserted

    [find_by!(provider: provider, provider_ref: ref), false]
  end

  # An application attempt failed (its transaction is already rolled back): count it and keep what went wrong,
  # in a transaction of its own with the lock wait bounded (a run holding the row must not pin this one). Never
  # raises, so it cannot hide the error being retried; a count lost to a lock timeout is only the count.
  def self.record_failure!(id, error)
    own_transaction("record_failure") do
      unapplied.where(id: id).update_all(
        ["attempts = attempts + 1, last_error = ?, updated_at = ?", error_summary(error), Time.current]
      )
    end
  rescue StandardError => e
    Rails.logger.error("[ProcessedOrder] could not record the failure of #{id}: #{e.class}")
  end

  # Retries are exhausted: the order is failed (staff re-run it) and reported with ids and the error class only.
  # A conditional update, so an order a concurrent run just applied stays applied. True when it was failed here.
  def self.mark_failed!(id, error)
    return false unless unapplied.where(id: id).where.not(status: "failed").update_all(status: "failed", updated_at: Time.current) == 1

    order = find(id)
    Rails.error.report(
      ApplyProcessedOrderJob::OrderApplyFailed.new(
        "order #{order.provider_ref} could not be applied after #{order.attempts} attempts (#{error.class})"
      ),
      handled: true, severity: :error,
      context: { shopify_order_id: order.provider_ref, attempts: order.attempts, error_class: error.class.name }
    )
    true
  end

  # An attempt failed and the order is still being retried (see ApplyProcessedOrderJob::WARN_AT_ATTEMPTS).
  def self.report_retrying(id, attempt, error)
    order = find_by(id: id)
    return unless order

    Rails.error.report(
      ApplyProcessedOrderJob::OrderApplyRetrying.new(
        "order #{order.provider_ref} failed attempt #{attempt}, retrying (#{error.class})"
      ),
      handled: true, severity: :warning,
      context: { shopify_order_id: order.provider_ref, attempt: attempt, error_class: error.class.name }
    )
  end

  # Staff re-run: a failed order goes back to received, counting its attempts afresh. A conditional update, so an
  # order a concurrent run just applied is left alone. True when it was reset here; the caller then queues the job.
  def reapply!
    self.class.where(id: id, status: "failed").update_all(status: "received", attempts: 0, updated_at: Time.current) == 1
  end

  # The error class and a short message for last_error. Never SQL (its text can carry values).
  def self.error_summary(error)
    detail = if error.is_a?(ActiveRecord::StatementInvalid) then ""
             elsif error.is_a?(ActiveRecord::RecordInvalid) then error.record&.errors&.full_messages.to_a.to_sentence
             else error.message.to_s
             end
    "#{error.class}: #{detail}".strip.delete_suffix(":").first(200)
  end
end
