# frozen_string_literal: true

# The inbox of payment-provider orders (see CreateProcessedOrders): the webhook stores the verified body with
# `receive!` and answers, ApplyProcessedOrderJob applies it. The unique key (provider, provider_ref) means one row
# per unit of work: the provider order for orders/paid, and a separate "<id>/fulfilled" unit for the cash-locker
# orders/fulfilled delivery of the same order (see ref_for). `topic` records which delivery the row came from.
# status: received (still to apply), applied, or failed (retries exhausted; staff re-run it with
# shop_orders:reapply). Rows are never deleted.
#
# The row is the scheduler, and its columns keep three jobs apart. next_attempt_at is only when a received order is next
# due: the webhook and a staff re-run set it to now, a failed run sets it to the backoff of its attempts, nothing else
# moves it. leased_until is the hand-out: dispatch_due (the only thing that enqueues ApplyProcessedOrderJob) claims due
# orders that nobody holds with one atomic UPDATE that sets it to now + LEASE, and the job it queues carries that value as
# its token. A run that still holds the token owns the order; one that does not (its lease expired and the order was
# handed out again, or a duplicate job) can neither start nor record a failure. attempts counts the runs that started
# (start_run! does it before any Shopify call), so a job waiting in a queue whose workers are down costs nothing, while a
# run that dies still counts: its lease just expires and the next dispatch retries, and when the MAX_ATTEMPTSth run dies
# the dispatcher marks the order failed (fail_exhausted). A failed run clears the lease and sets the backoff. reported_at
# is when an order that has been due for hours (workers or queue down, or runs that keep dying) was last reported (see
# report_stranded).
class ProcessedOrder < ApplicationRecord
  # Raised only to be reported (Rails.error.report).
  class SpentOrderStepFailed < StandardError; end

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

  # Hands out the due received orders that nobody holds (optionally only `id`) and enqueues one ApplyProcessedOrderJob
  # for each, with its lease as the token, then returns the ids it queued. Handing out is ONE atomic UPDATE that sets
  # leased_until to now + LEASE (rows another dispatcher has locked are skipped, so none is handed out twice) and
  # touches nothing else. An order whose last attempt is spent is never handed out (see fail_exhausted). A job that
  # cannot be queued gives the lease back, so the next dispatch hands the order out again. Never raises.
  # It first marks the spent orders failed unless the caller has done so (skip_fail_exhausted: true): the dispatcher job
  # does that once before its rounds, since handing out never spends an attempt.
  def self.dispatch_due(id: nil, now: Time.current, skip_fail_exhausted: false)
    fail_exhausted(id: id, now: now) unless skip_fail_exhausted
    where_id = id ? sanitize_sql_array(["AND id = ?", id]) : ""
    rows = connection.select_all(sanitize_sql_array([<<~SQL.squish, now, now, MAX_ATTEMPTS, BATCH, now + LEASE])).cast_values
      WITH due AS (
        SELECT id FROM processed_orders
        WHERE status = 'received' AND next_attempt_at <= ? AND (leased_until IS NULL OR leased_until <= ?)
          AND attempts < ? #{where_id}
        ORDER BY next_attempt_at LIMIT ? FOR UPDATE SKIP LOCKED
      )
      UPDATE processed_orders o SET leased_until = ?
      FROM due WHERE o.id = due.id RETURNING o.id, o.leased_until
    SQL
    queued_ids = []
    rows.each do |order_id, token|
      queued = begin
        ApplyProcessedOrderJob.perform_later(order_id, token)
      rescue StandardError => e
        Rails.logger.error("[ProcessedOrder] could not queue order #{order_id}: #{e.class}")
        false
      end
      if queued
        queued_ids << order_id
      else
        where(id: order_id, leased_until: token).update_all(leased_until: nil)
      end
    end
    queued_ids
  rescue StandardError => e
    Rails.logger.error("[ProcessedOrder] dispatch failed: #{e.class}")
    []
  end

  # A run starts: counts the attempt, before anything else is done, if the run still holds the order (received, and
  # `token` is its lease). In the same UPDATE the lease is replaced by a fresh one (now + LEASE), so the run has a full
  # lease from its start and a duplicate job holding the original token no longer matches. Returns [attempts, new token]
  # (the token as the database stored it), or nil when the token is stale, the job a duplicate, or the order already
  # settled, in which case the run must do nothing. The wait on a row another run is applying is bounded.
  def self.start_run!(id, token, now: Time.current)
    return if token.nil?

    sql = "UPDATE processed_orders SET attempts = attempts + 1, leased_until = ?, updated_at = ? " \
          "WHERE id = ? AND status = 'received' AND leased_until = ? RETURNING attempts, leased_until"
    own_transaction("start_run") do
      connection.select_all(sanitize_sql_array([sql, now + LEASE, now, id, token])).cast_values.first
    end
  end

  # Marks failed (and reports, ids only) the received orders whose MAX_ATTEMPTSth run started and never recorded an
  # outcome: every attempt is spent and its lease has expired, so the run died. A spent order left with no lease at all
  # is failed the same way, as a backstop. The last real error is kept, with a note that the last attempt did not
  # finish. Rows locked by a running apply are skipped, never waited for. Without this such an order would be handed
  # out for ever. Returns the provider refs failed. Never raises: a failure is reported (class only, the message of a
  # database error can carry SQL and order values) and the caller goes on to hand out what is due, so every entry
  # point (the dispatcher job, a webhook's dispatch_due) behaves the same.
  def self.fail_exhausted(id: nil, now: Time.current)
    where_id = id ? sanitize_sql_array(["AND id = ?", id]) : ""
    rows = connection.select_rows(sanitize_sql_array([<<~SQL.squish, MAX_ATTEMPTS, now, " (then the last attempt did not finish)", "the last attempt did not finish", now]))
      WITH spent AS (
        SELECT id FROM processed_orders
        WHERE status = 'received' AND attempts >= ? AND (leased_until IS NULL OR leased_until <= ?) #{where_id}
        FOR UPDATE SKIP LOCKED
      )
      UPDATE processed_orders o SET status = 'failed', leased_until = NULL, last_error = COALESCE(o.last_error || ?, ?), updated_at = ?
      FROM spent WHERE o.id = spent.id RETURNING o.provider_ref, o.attempts
    SQL
    rows.each do |ref, attempts|
      Rails.error.report(
        ApplyProcessedOrderJob::OrderApplyFailed.new(
          "order #{ref} could not be applied after #{attempts} attempts (the last one did not finish)"
        ), handled: true, severity: :error, context: { shopify_order_id: ref, attempts: attempts, error_class: "AttemptDidNotFinish" }
      )
    end
    rows.map(&:first)
  rescue StandardError => e
    Rails.error.report(
      SpentOrderStepFailed.new("marking the spent orders failed raised (#{e.class})"),
      handled: true, severity: :error, context: { step: "fail_exhausted", error_class: e.class.name }
    )
    []
  end

  # An application attempt failed (its transaction is already rolled back). Only the run that still holds the order
  # (received, `token` is its lease) records it: in a small transaction with the lock wait bounded (a run holding the row
  # must not pin this one) the order keeps the error, gives up the lease and is scheduled after the backoff of its
  # attempts; its MAX_ATTEMPTSth failure marks it failed instead. Then it is reported by the row's own attempts:
  # OrderApplyRetrying at attempts 1 and 5, OrderApplyFailed at the end. A run that does not hold the order (settled, or
  # handed out again) changes nothing, but its error is reported as a warning, so it is never lost. Never raises, so it
  # cannot hide the error: a failure recorded nowhere (the database is down) leaves the lease to expire and the order to
  # be dispatched again.
  def self.record_failure!(id, token, error)
    order = own_transaction("record_failure") do
      row = where(status: "received", leased_until: token).lock.find_by(id: id) unless token.nil?
      next unless row

      if row.attempts >= MAX_ATTEMPTS
        row.update!(last_error: error_summary(error), status: "failed", leased_until: nil)
      else
        row.update!(last_error: error_summary(error), leased_until: nil, next_attempt_at: Time.current + backoff(row.attempts))
      end
      row
    end
    order ? report_attempt(order, error) : report_unrecorded(id, error)
  rescue StandardError => e
    Rails.logger.error("[ProcessedOrder] could not record the failure of #{id}: #{e.class}")
  end

  # The error is wrapped (class only): its message can carry values from the order.
  def self.report_unrecorded(id, error)
    row = find_by(id: id)
    Rails.error.report(
      ApplyProcessedOrderJob::StaleRunFailed.new(
        "a run of order #{row&.provider_ref || id} failed without holding it (#{error.class})"
      ), handled: true, severity: :warning,
         context: { shopify_order_id: row&.provider_ref, status: row&.status, error_class: error.class.name,
                    note: "failure of a run that no longer holds the order" }
    )
  end
  private_class_method :report_unrecorded

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

  # Reports (ids only) the received orders that have been due for more than STRANDED_AFTER, at most once per
  # REPORT_EVERY each: the reported ones are stamped in the same UPDATE that selects them. A hand-out does not move
  # next_attempt_at, so this means no run has recorded an outcome for two hours: the workers or the queue are down,
  # or runs keep dying. A backlog the dispatcher is working through is not reported (it hands out in rounds).
  # Returns the provider refs reported.
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
        .update_all(status: "received", attempts: 0, next_attempt_at: now, leased_until: nil, last_error: nil, reported_at: nil,
                    updated_at: now) == 1
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
