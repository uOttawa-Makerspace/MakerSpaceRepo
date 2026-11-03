# frozen_string_literal: true

# The inbox of payment-provider orders (see CreateProcessedOrders): the webhook stores the verified body with
# `receive!` and answers, ApplyProcessedOrderJob applies it. The unique key (provider, provider_ref) means one row
# per unit of work: the provider order for orders/paid, and a separate "<id>/fulfilled" unit for the cash-locker
# orders/fulfilled delivery of the same order (see ref_for). `topic` records which delivery the row came from.
# status: received (still to apply), applied, or failed (retries exhausted; staff re-run it with
# shop_orders:reapply). Rows are never deleted.
#
# The row is the scheduler. A received order is due when next_attempt_at has passed; dispatch_due hands due rows out
# (and only it enqueues ApplyProcessedOrderJob) by moving next_attempt_at forward by a lease in the same atomic
# UPDATE, so a row cannot be handed out twice while a job for it is pending or running, and a job that dies just
# lets the lease expire. A failed run overwrites next_attempt_at with the backoff of its attempts; the MAX_ATTEMPTSth
# failure marks the order failed. reported_at is when a stranded order (see report_stranded) was last reported.
class ProcessedOrder < ApplicationRecord
  STATUSES = %w[received applied failed].freeze
  MAX_ATTEMPTS = 10
  WARN_AT_ATTEMPTS = [1, 5].freeze
  LEASE = 15.minutes
  BATCH = 200
  STRANDED_AFTER = 2.hours
  REPORT_EVERY = 1.hour
  # How long an applied order keeps its payload (the customer data Shopify sent); see purge_payloads!.
  PAYLOAD_RETENTION = 90.days

  # The wait before the retry that follows failed attempt number `attempts` (1..9): 61s, 92s, 5m, 18m, 53m,
  # 2h10m, 4h41m, 9h07m, 16h25m (about 34 hours over the nine waits).
  def self.backoff(attempts) = (attempts**5 + 60).seconds

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
         next_attempt_at: now, created_at: now, updated_at: now }],
      unique_by: %i[provider provider_ref], returning: %w[id]
    ).rows.first
    return [find(inserted.first), true] if inserted

    [find_by!(provider: provider, provider_ref: ref), false]
  end

  # Hands out the due received orders (optionally only `id`) and enqueues one ApplyProcessedOrderJob for each, then
  # returns the ids it queued. Handing out is ONE atomic UPDATE that moves next_attempt_at to now + LEASE (a concurrent
  # dispatcher waits on the locked rows and then finds them no longer due), so an order is queued once per lease.
  # A job that cannot be queued gives its lease back (the order keeps its old due time, so it is picked up by the
  # next dispatch and is reported as stranded if that never works). Never raises.
  def self.dispatch_due(id: nil, now: Time.current)
    leased_until = now + LEASE
    where_id = id ? sanitize_sql_array(["AND id = ?", id]) : ""
    rows = connection.select_rows(sanitize_sql_array([<<~SQL.squish, now, BATCH, leased_until, now]))
      WITH due AS (
        SELECT id, next_attempt_at AS previous FROM processed_orders
        WHERE status = 'received' AND next_attempt_at <= ? #{where_id}
        ORDER BY next_attempt_at LIMIT ? FOR UPDATE
      )
      UPDATE processed_orders o SET next_attempt_at = ?, updated_at = ?
      FROM due WHERE o.id = due.id RETURNING o.id, due.previous
    SQL
    queued_ids = []
    rows.each do |order_id, previous|
      queued = begin
        ApplyProcessedOrderJob.perform_later(order_id)
      rescue StandardError => e
        Rails.logger.error("[ProcessedOrder] could not queue order #{order_id}: #{e.class}")
        false
      end
      if queued
        queued_ids << order_id
      else
        where(id: order_id, status: "received", next_attempt_at: leased_until).update_all(next_attempt_at: previous)
      end
    end
    queued_ids
  rescue StandardError => e
    Rails.logger.error("[ProcessedOrder] dispatch failed: #{e.class}")
    []
  end

  # An application attempt failed (its transaction is already rolled back). In a small transaction with the lock
  # wait bounded (a run holding the row must not pin this one) the received order counts the attempt, keeps the
  # error and is scheduled after its backoff; its MAX_ATTEMPTSth failure marks it failed instead. Then it is
  # reported by the row's own attempts: OrderApplyRetrying at attempts 1 and 5, OrderApplyFailed at the end. An
  # applied or already failed order is left alone. Never raises, so it cannot hide the error: a failure recorded
  # nowhere (the database is down) leaves the lease to expire and the order to be dispatched again.
  def self.record_failure!(id, error)
    order = own_transaction("record_failure") do
      row = where(status: "received").lock.find_by(id: id)
      next unless row

      attempts = row.attempts + 1
      if attempts >= MAX_ATTEMPTS
        row.update!(attempts: attempts, last_error: error_summary(error), status: "failed")
      else
        row.update!(attempts: attempts, last_error: error_summary(error), next_attempt_at: Time.current + backoff(attempts))
      end
      row
    end
    report_attempt(order, error) if order
  rescue StandardError => e
    Rails.logger.error("[ProcessedOrder] could not record the failure of #{id}: #{e.class}")
  end

  def self.report_attempt(order, error)
    context = { shopify_order_id: order.provider_ref, attempts: order.attempts, error_class: error.class.name }
    if order.status == "failed"
      Rails.error.report(
        ApplyProcessedOrderJob::OrderApplyFailed.new(
          "order #{order.provider_ref} could not be applied after #{order.attempts} attempts (#{error.class})"
        ), handled: true, severity: :error, context: context
      )
    elsif WARN_AT_ATTEMPTS.include?(order.attempts)
      Rails.error.report(
        ApplyProcessedOrderJob::OrderApplyRetrying.new(
          "order #{order.provider_ref} failed attempt #{order.attempts}, retrying (#{error.class})"
        ), handled: true, severity: :warning, context: context
      )
    end
  end
  private_class_method :report_attempt

  # Reports (ids only) the received orders that are more than STRANDED_AFTER overdue, which only happens when
  # nothing dispatches them (a dispatched order is due in the future), at most once per REPORT_EVERY each: the
  # reported ones are stamped in the same UPDATE that selects them. Returns the provider refs reported.
  def self.report_stranded(now: Time.current)
    rows = connection.select_rows(sanitize_sql_array([<<~SQL.squish, now, now - STRANDED_AFTER, now - REPORT_EVERY]))
      UPDATE processed_orders SET reported_at = ?
      WHERE status = 'received' AND next_attempt_at < ? AND (reported_at IS NULL OR reported_at < ?)
      RETURNING provider_ref, attempts
    SQL
    rows.each do |ref, attempts|
      Rails.error.report(
        DispatchDueOrdersJob::StrandedOrder.new("order #{ref} has been waiting to be applied for over 2 hours"),
        handled: true, severity: :error, context: { shopify_order_id: ref, attempts: attempts }
      )
    end
    rows.map(&:first)
  end

  # Blanks (payload = '{}') the payload of every order applied more than PAYLOAD_RETENTION ago, in batches of BATCH
  # rows, one UPDATE per batch. The row stays: it is the idempotency key, so a resent order is still skipped. Received
  # and failed orders are never touched (staff re-run a failed one from its payload), and a row already blank is
  # skipped, so a second run changes nothing. Returns the number of rows blanked.
  def self.purge_payloads!(now: Time.current)
    total = 0
    loop do
      ids = where(status: "applied", applied_at: ...(now - PAYLOAD_RETENTION))
            .where.not(payload: {}).order(:id).limit(BATCH).pluck(:id)
      return total if ids.empty?

      total += where(id: ids, status: "applied").update_all(payload: {}, updated_at: now)
    end
  end

  # Staff re-run: a failed order goes back to received, due now, counting its attempts afresh. A conditional
  # update, so an order a concurrent run just applied is left alone. True when it was reset here; the caller then
  # dispatches it.
  def reapply!(now: Time.current)
    self.class.where(id: id, status: "failed")
        .update_all(status: "received", attempts: 0, next_attempt_at: now, reported_at: nil, updated_at: now) == 1
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
