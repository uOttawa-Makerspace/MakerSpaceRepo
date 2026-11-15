# frozen_string_literal: true

# Applies one stored Shopify order (a ProcessedOrder row) to the site: the locker payment, the membership paid and
# the CC Money credit of an orders/paid delivery, or the locker payment of an orders/fulfilled (cash) one. The row's
# PaymentEvent names the products the order is for, and HANDLERS maps each kind to the handler that applies it.
#
# Everything is applied in ONE transaction together with the row's status change, with the lock waits bounded
# (own_transaction), after the row is locked FOR UPDATE: a second run of the same order finds it applied and does
# nothing, and any error rolls the whole application back, so a branch either applies or the order is retried (see
# ApplyProcessedOrderJob). Shopify is only asked (draft-order metafields) BEFORE the transaction, so no HTTP call
# holds a lock. Problems that are decisions rather than errors (the order names a membership or locker rental that
# does not exist, a CC order without an email, a refused metafield lookup) apply what can be applied and are
# reported for staff, after the commit, so a rolled-back attempt reports nothing. The CC claim mail is queued
# after the commit as well (Active Job here enqueues at once: enqueue_after_transaction_commit is false).
class ShopOrderApplier
  # Raised only to be reported (Rails.error.report).
  class LockerOrderWithoutReference < StandardError; end
  class UnknownLockerRental < StandardError; end
  class UnknownMembership < StandardError; end
  class UnresolvedMembershipOrder < StandardError; end
  class MembershipNotPending < StandardError; end
  class UnresolvedCcOrder < StandardError; end
  # Shopify refused a metafield lookup for good (an access or invalid-id error): reported once, and the order goes
  # on without that reference. The locker and membership branches that needed it apply nothing (the reference is
  # unknown, not absent); the others apply as designed.
  class MetafieldLookupRejected < StandardError; end

  PROVIDER = "shopify"

  # The handler of each kind of product a payment can be for (Payments::Reference::KINDS), in the order they apply.
  # Job orders have none: staff record a job-order payment by hand (the webhook logs it). A cash payment is applied
  # only by a handler that takes cash (lockers).
  HANDLERS = { "locker" => LockerHandler, "membership" => MembershipHandler, "cc_money" => CcMoneyHandler }.freeze

  # What one stored order asks for: its PaymentEvent and the handlers that apply it, from the payload alone. The
  # metafield values that name the records, and a refused lookup, are filled in by the Shopify lookup
  # (resolve_references).
  Plan = Struct.new(:hook, :id, :event, :handlers, :metafields, :lookup_rejection, :left_unapplied,
                    keyword_init: true) do
    def metafield(key) = metafields.fetch(key, nil)
    def left_unapplied?(kind) = Array(left_unapplied).include?(kind.to_sym)
  end

  # The handlers that apply the payment of `event`: none for plain merch, job orders, products of another
  # environment and cancellations.
  def self.handlers_for(event)
    HANDLERS.values.select { |handler| handler.applies_to?(event) }
  end

  # Whether the webhook stores `event`: a payment some handler applies, or the cancellation of an order for any product
  # the app tracks. A cancellation is only recorded for now: no handler acts on it, so applying its row changes nothing
  # but the row (status applied, topic orders/cancelled), and its payload is kept (purge_payloads!).
  def self.stores?(event)
    event.cancelled ? event.kinds.any? : handlers_for(event).any?
  end

  def initialize(record)
    @record = record
    @refusals = []
  end

  def call
    plan = plan_for(@record)
    resolve_references(plan)

    ApplicationRecord.own_transaction("apply_processed_order") do
      order = ProcessedOrder.lock.find(@record.id)
      next unless order.status == "received"

      apply(plan)
      order.update!(status: "applied", applied_at: Time.current, last_error: ProcessedOrder.refusal_note(@refusals),
                    leased_until: nil)
      @applied_here = true
    end
  rescue StandardError => e
    raise unless post_commit_failure?

    # The order committed as applied and something that runs after the commit raised: not a failed attempt (the
    # order must not be applied again), so tell staff, who can resend whatever it was.
    report_after_commit_failure(e, "after_commit")
  end

  # ---- what the handlers use

  # Reports a problem for staff to reconcile. Sent once the transaction has committed, so an attempt that rolls
  # back (and is retried) reports nothing and a retry does not report twice.
  def report_problem(error, context: {})
    after_commit("problem_report") { Rails.error.report(error, handled: true, severity: :error, context: context) }
  end

  # An order whose target cannot be found, which no retry can fix: reported with the order id and left to staff.
  # The order is still applied.
  def report_unresolved(plan, error_class, branch, message, **extra_context)
    report_problem(error_class.new("#{branch} order #{plan.id} #{message}"),
                   context: { shopify_order_id: plan.id }.merge(extra_context))
  end

  # Records a refused part of the order on the applied row (see ProcessedOrder.refused).
  def refuse(detail)
    @refusals << detail
  end

  # Runs a side effect once the transaction has committed. If it raises, the order is already applied, so the failure
  # is reported (order id and which side effect, no personal data) instead of failing the attempt.
  def after_commit(side_effect, &block)
    ActiveRecord.after_all_transactions_commit do
      block.call
    rescue StandardError => e
      report_after_commit_failure(e, side_effect)
    end
  end

  private

  def plan_for(record)
    event = record.payment_event
    Plan.new(hook: record.payload, id: Payments::ShopifyAdapter::Order.order_id(record.payload), event: event,
             handlers: self.class.handlers_for(event), metafields: {})
  end

  def apply(plan)
    log_cancellation(plan) if plan.event.cancelled
    report_lookup_rejection(plan)
    plan.handlers.each { |handler| handler.new(self, plan).call }
  end

  # A cancelled order is recorded (its row is marked applied) and nothing else changes.
  def log_cancellation(plan)
    Rails.logger.info("[ShopOrderApplier] cancelled order #{plan.id} recorded; no action taken")
  end

  # ---- Shopify lookup (before the transaction)

  def draft_order_gid_from_hook(hook)
    if hook["draft_order_id"].present?
      "gid://shopify/DraftOrder/#{hook['draft_order_id']}"
    else
      hook["admin_graphql_api_id"]
    end
  end

  # The values of the makerepo metafields the handlers need (each handler's metafield_key): from the payload when it
  # carries them, else from ONE Shopify lookup of the draft order shared by all the keys
  # (Payments::ShopifyAdapter::Metafields). It can raise when Shopify is not configured or the lookup must be retried
  # (the job retries). A lookup Shopify refuses for good yields no values and is noted on the plan, so the order
  # proceeds as "no reference".
  def resolve_references(plan)
    @remote = :unfetched
    plan.metafields = plan.handlers.each_with_object({}) do |handler, values|
      key = handler.metafield_key(plan.hook)
      values[key] = metafield_value(plan, handler, key) if key
    end
  end

  def metafield_value(plan, handler, key)
    field = payload_metafield(plan.hook, key) || remote_metafield(plan, handler, key)
    field&.[]("value").presence
  end

  def payload_metafield(hook, key)
    hook["metafields"]&.find { |m| m["namespace"] == "makerepo" && m["key"] == key }
  end

  # The field from the one Shopify lookup of the order. When that lookup was refused, the reference is unknown, not
  # absent, so the product is left unapplied (and reported with the refusal) instead of being treated as one without
  # a reference.
  def remote_metafield(plan, handler, key)
    @remote = fetch_remote_metafields(plan) if @remote == :unfetched
    (plan.left_unapplied ||= []) << handler.kind.to_sym if plan.lookup_rejection
    @remote&.find { |f| f["key"] == key }
  end

  def fetch_remote_metafields(plan)
    draft_order_metafields(draft_order_gid_from_hook(plan.hook))
  rescue Payments::ShopifyAdapter::Metafields::REJECTED => e
    plan.lookup_rejection = e.codes
    nil
  end

  def draft_order_metafields(gid) = Payments::ShopifyAdapter::Metafields.of(gid)

  # ---- reports

  # The error is wrapped (class only): its message can carry values from the order.
  def report_after_commit_failure(error, side_effect)
    Rails.error.report(
      ApplyProcessedOrderJob::PostCommitSideEffectFailed.new(
        "order #{@record.provider_ref} was applied but its #{side_effect} failed (#{error.class})"
      ), handled: true, severity: :error,
         context: { shopify_order_id: @record.provider_ref, side_effect: side_effect, error_class: error.class.name }
    )
  end

  # True when this run committed the order as applied (so an error now came after the commit, not from the attempt).
  def post_commit_failure?
    @applied_here && ProcessedOrder.where(id: @record.id, status: "applied").exists?
  end

  # One report per cause, and the cause is the refusal: it names the products it left unapplied (the locker and
  # membership branches of an order whose reference it was meant to supply). Those branches send no report of
  # their own; orders that really carry no reference, with nothing refused, are still reported per product.
  def report_lookup_rejection(plan)
    return unless plan.lookup_rejection

    affected = Array(plan.left_unapplied)
    report_problem(
      MetafieldLookupRejected.new(
        "metafield lookup for order #{plan.id} rejected (#{plan.lookup_rejection.join(', ')}); " \
        "left unapplied: #{affected.join(', ').presence || 'nothing'}"
      ),
      context: { shopify_order_id: plan.id, codes: plan.lookup_rejection, affected: affected }
    )
  end
end
