# frozen_string_literal: true

require Rails.root.join("lib/report_throttle")

# Shopify webhooks
class CustomWebhooksController < ApplicationController
  # Shopify sends no CSRF token and no session cookie; the caller is authenticated by
  # the X-Shopify-Hmac-Sha256 signature below (ShopifyApp::WebhookVerification, which
  # also skips the check, but only outside development, so the skip is stated here).
  skip_forgery_protection
  # Webhook verification is on in every environment, test included, so specs sign their
  # payloads and can detect its removal. Only development is exempt (decided once, at load
  # time) so unsigned webhooks can be replayed locally (e.g. with curl) without the secret.
  unless Rails.env.development?
    # 1. Fail closed when no webhook secret is configured (production/staging without the
    #    credential): the app boots, but every request is refused with 503 and reported.
    #    503 (not 401) because it is OUR misconfiguration, and Shopify retries non-2xx
    #    webhooks, so deliveries are processed once the secret is set.
    before_action :require_webhook_secret!
    # 2. A request with no X-Shopify-Hmac-Sha256 header would make the gem's
    #    secure_compare(nil, ..) raise (500); answer 401 before the gem's check instead.
    before_action :require_hmac_header!
    # 3. The gem's HMAC check (X-Shopify-Hmac-Sha256), added after the two above so they run first.
    include ShopifyApp::WebhookVerification
  end
  include ShopifyConcern

  # The money branches (locker activation, membership paid, CC credit) apply all together or not at all:
  #   1. classify the order once (OrderPlan) and resolve its draft-order metafield references. This is the only
  #      part that reaches Shopify, so the only part that can fail on Shopify (not configured, throttled, an error
  #      answer); nothing is written yet and the answer is 503, so Shopify retries.
  #   2. apply the branches in ONE transaction (apply_claimed_order), together with the order's claim in
  #      processed_orders.
  # A claimed order is an applied order, and every branch either applies or is reported. A transient failure
  # (a database error, a lock timeout) rolls the whole transaction back, claim included, and answers 500 so Shopify
  # retries. A problem no retry can fix is reported with the order id and the claim is committed, so it is neither
  # retried forever nor lost; it never blocks the other branches (each of the membership and CC branches runs in
  # its own savepoint). Reports go out after the commit, so a rolled-back attempt reports nothing.
  # An order with a membership or CC branch is applied once per Shopify order (the claim, whose unique key
  # also covers a repeated delivery). A locker-only order has no claim: locker_payments, keyed by the
  # order id, is its ledger (shared with orders_fulfilled).
  def orders_paid
    plan = order_plan(webhook_params.to_h)

    # An order that was already claimed is applied: answer before any Shopify lookup.
    if plan.claimable? && plan.id.present? && ProcessedOrder.exists?(provider: SHOP_PROVIDER, provider_ref: plan.id.to_s)
      Rails.logger.info("[orders_paid] order #{plan.id} already applied, nothing to do")
      return head :ok
    end

    begin
      resolve_references(plan)
    rescue ShopifyContext::NotConfigured, ShopifyConcern::MetafieldLookupFailed => e
      Rails.logger.warn("[orders_paid] Shopify lookup unavailable, answering 503 (Shopify will retry): #{e.class}")
      return head :service_unavailable
    end

    # Job-order payment is recorded by staff, not automatically. Leave a trace so a
    # paid job-order draft order can be reconciled by hand.
    if plan.job_order?
      Rails.logger.info(
        "[orders_paid] paid job-order draft order ignored (no automatic payment recording): " \
        "order id=#{plan.hook['id'].inspect} name=#{plan.hook['name'].inspect} " \
        "draft_order_id=#{plan.hook['draft_order_id'].inspect}"
      )
    end

    if plan.claimable? && plan.id.present?
      apply_claimed_order(plan)
    else
      apply_locker_alone(plan.hook, plan.locker_ref) if plan.locker?
      report_order_without_id(plan) if plan.claimable?
    end

    head :ok
  end

  # Cash locker payments. Staff fulfil a cash order in Shopify without marking it paid, so the fulfillment
  # is the payment event. Only the locker branch runs, and only while Shopify still shows the payment as
  # pending: a paid order is handled by orders_paid, and a refunded, voided or partly paid one is not a
  # cash payment. The locker payment record is keyed by the Shopify order id, so an orders_paid for the
  # same order later applies nothing a second time. Memberships and CC Money paid in cash stay with staff.
  def orders_fulfilled
    order_hook = webhook_params.to_h
    return head :ok unless order_hook["financial_status"] == "pending" &&
                           LockerRental.draft_order_processable?(order_hook["tags"])

    begin
      locker_ref = metafield_values(order_hook, [LOCKER_KEY])[LOCKER_KEY]
    rescue ShopifyContext::NotConfigured, ShopifyConcern::MetafieldLookupFailed => e
      Rails.logger.warn("[orders_fulfilled] Shopify lookup unavailable, answering 503 (Shopify will retry): #{e.class}")
      return head :service_unavailable
    end

    # The cash was taken when the order was fulfilled, not when it was created (processed_at)
    fulfilled_at = Array(order_hook["fulfillments"]).filter_map { |f| parse_time(f["created_at"]) }.max
    apply_locker_alone(order_hook, locker_ref, paid_at: fulfilled_at || Time.current)
    head :ok
  end

  # Raised only to be reported (Rails.error.report).
  class LockerOrderWithoutId < StandardError; end
  class LockerOrderWithoutReference < StandardError; end
  class UnknownLockerRental < StandardError; end
  class OrderWithoutId < StandardError; end
  class UnknownMembership < StandardError; end
  class UnresolvedMembershipOrder < StandardError; end
  class UnresolvedCcOrder < StandardError; end
  # Shopify refused a metafield lookup for good (an access or invalid-id error): reported, the order goes on.
  class MetafieldLookupRejected < StandardError; end
  # What a branch raises is permanent unless it is one of these: they roll back the whole order and answer
  # 500, so Shopify retries it.
  TRANSIENT_ERRORS = [
    ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed, ActiveRecord::LockWaitTimeout,
    ActiveRecord::QueryCanceled, ActiveRecord::StatementTimeout, ActiveRecord::Deadlocked,
    ActiveRecord::SerializationFailure, ShopifyConcern::MetafieldLookupFailed, ShopifyContext::NotConfigured
  ].freeze
  # A membership or CC branch whose write was refused by validation: permanent, the other branches still apply.
  class BranchRejected < StandardError; end

  # What one orders/paid payload asks for, classified once. The references are filled in by the Shopify lookups.
  OrderPlan = Struct.new(:hook, :id, :locker, :membership, :job_order, :email, :cc_items, :locker_ref, :membership_ref,
                         keyword_init: true) do
    alias_method :locker?, :locker
    alias_method :membership?, :membership
    alias_method :job_order?, :job_order

    # Has something to claim: a membership order, or one with the CC product. Plain merch, job-order and
    # locker-only orders have none.
    def claimable? = membership? || cc_items.any?
  end

  SHOP_PROVIDER = "shopify"
  CC_PRODUCT_ID = 4_359_597_129_784

  private

  def require_hmac_header!
    head :unauthorized if request.headers["HTTP_X_SHOPIFY_HMAC_SHA256"].blank?
  end

  MISSING_SECRET_REPORT_THROTTLE = ReportThrottle.new(interval: 10.minutes)

  class << self
    # True at most once per 10 minutes per process, so a Shopify retry storm cannot flood the
    # error tracker. The requests themselves are always refused.
    def report_missing_secret?
      MISSING_SECRET_REPORT_THROTTLE.allow?(:missing_secret)
    end

    def reset_missing_secret_report_throttle!
      MISSING_SECRET_REPORT_THROTTLE.reset!
    end
  end

  def require_webhook_secret!
    return if ShopifyWebhookSecret.configured?(ShopifyApp.configuration.secret) ||
              ShopifyWebhookSecret.configured?(ShopifyApp.configuration.old_secret)

    if self.class.report_missing_secret?
      error = ShopifyWebhookSecret::MissingSecret.new(
        "Shopify webhook secret is not configured (credentials.#{Rails.env}.shopify.webhook); refusing webhooks (503)"
      )
      Rails.error.report(error, handled: true, severity: :error, context: { path: request.path })
      Airbrake.notify(error) if defined?(Airbrake) && Airbrake.configured?
    end
    head :service_unavailable
  end

  def webhook_params
    params.permit!
  end

  def draft_order_gid_from_hook(order_hook)
    if order_hook["draft_order_id"].present?
      "gid://shopify/DraftOrder/#{order_hook['draft_order_id']}"
    else
      order_hook["admin_graphql_api_id"]
    end
  end

  LOCKER_KEY = "locker_db_reference"
  MEMBERSHIP_KEY = "membership_db_reference"

  # The values of the makerepo metafields `keys` of an order: from the payload when it carries them, else from
  # ONE Shopify lookup of the draft order shared by all the keys (the only part that reaches Shopify; it can
  # raise ShopifyContext::NotConfigured or ShopifyConcern::MetafieldLookupFailed, both retried). A lookup
  # Shopify refuses for good yields no values and is reported, so the order proceeds as "no reference".
  def metafield_values(order_hook, keys)
    remote = :unfetched
    keys.index_with do |key|
      field = order_hook["metafields"]&.find { |m| m["namespace"] == "makerepo" && m["key"] == key }
      if field.nil?
        remote = fetch_remote_metafields(order_hook) if remote == :unfetched
        field = remote&.find { |f| f["key"] == key }
      end
      field&.[]("value").presence
    end
  end

  def fetch_remote_metafields(order_hook)
    draft_order_metafields(draft_order_gid_from_hook(order_hook))
  rescue ShopifyConcern::MetafieldLookupRejected => e
    report_problem(
      MetafieldLookupRejected.new("metafield lookup for order #{order_id(order_hook)} rejected (#{e.codes.join(', ')})"),
      context: { shopify_order_id: order_id(order_hook), codes: e.codes }
    )
    nil
  end

  # Phase 1: the locker and membership references the plan needs (a membership order without line items has
  # nothing to look up).
  def resolve_references(plan)
    keys = []
    keys << LOCKER_KEY if plan.locker?
    keys << MEMBERSHIP_KEY if plan.membership? && plan.hook["line_items"].present?
    values = metafield_values(plan.hook, keys)
    plan.locker_ref = values[LOCKER_KEY]
    plan.membership_ref = values[MEMBERSHIP_KEY]
  end

  # The Shopify order id: the payload's numeric "id", else the numeric tail of its admin_graphql_api_id
  # ("gid://shopify/Order/123"), so both spellings of one order are the same idempotency key.
  def order_id(order_hook)
    order_hook["id"].presence&.to_s || order_hook["admin_graphql_api_id"].presence&.to_s&.split("/")&.last
  end

  # The locker branch of a paid (orders_paid) or cash (orders_fulfilled) order.
  def apply_locker_order(order_hook, locker_ref, paid_at: nil)
    # A locker-tagged order that names no locker rental at all: nothing to apply, and not to be lost
    # silently either (staff reconcile it from the report). Still 200.
    if locker_ref.blank?
      report_problem(
        LockerOrderWithoutReference.new("locker order #{order_id(order_hook)} carries no locker_db_reference"),
        context: { shopify_order_id: order_id(order_hook) }
      )
      return
    end

    # A locker order must carry the Shopify order id (it is the idempotency key of the payment record).
    # Shopify always sends it, so a missing one is a bug on our side or theirs: skip ONLY the locker branch
    # (never answer an error for the whole order, which would be retried forever and block the membership
    # and CC branches), and report it with ids only so staff can reconcile the rental by hand.
    if order_id(order_hook).blank?
      report_problem(
        LockerOrderWithoutId.new("locker order without an order id; locker branch skipped (rental #{locker_ref})"),
        context: { locker_rental_id: locker_ref }
      )
      return
    end

    process_locker_hook(locker_ref, order_hook, paid_at: paid_at)
  end

  def process_locker_hook(locker_id, order_hook, paid_at: nil)
    return unless locker_id.present?

    rental = LockerRental.find_by(id: locker_id)
    unless rental
      # Answer 200 (a retry cannot fix it) but never silently: a paid order points at a rental that is gone.
      report_problem(
        UnknownLockerRental.new("locker order #{order_id(order_hook)} references unknown locker rental #{locker_id}"),
        context: { locker_rental_id: locker_id.to_s, shopify_order_id: order_id(order_hook) }
      )
      return
    end

    # amount = the locker line only (nil when it cannot be told); order_total = the whole order. A malformed
    # or out-of-range figure is stored as nil and never fails the webhook; record_payment reports it (ids only)
    # after its commit, and only when the payment row is really new, so a replayed delivery does not report it again.
    problems = []
    rental.record_payment(
      shopify_order_id: order_id(order_hook),
      paid_at: paid_at || parse_time(order_hook["processed_at"]) || Time.current,
      amount: safe_money(problems, "locker line amount") { rental.locker_line_amount(order_hook["line_items"]) },
      order_total: safe_money(problems, "order total") { LockerPayment.money(order_hook["total_price"]) },
      currency: order_hook["currency"].presence&.to_s&.first(8),
      malformed_amounts: problems
    )
  end

  def safe_money(problems, what)
    yield
  rescue ArgumentError
    problems << what
    nil
  end

  def parse_time(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  # The plan of one payload: every predicate and list the branches and reports read, computed here once.
  def order_plan(order_hook)
    tags = order_hook["tags"]
    email = order_hook.dig("customer", "email").presence
    cc_items = Array.wrap(order_hook["line_items"]).select { |i| i.is_a?(Hash) && i["product_id"].to_i == CC_PRODUCT_ID }
    OrderPlan.new(hook: order_hook, id: order_id(order_hook), email: email, cc_items: cc_items,
                  locker: LockerRental.draft_order_processable?(tags),
                  membership: Membership.draft_order_processable?(tags),
                  job_order: JobOrder.draft_order_processable?(tags))
  end

  # Reports a problem for staff to reconcile. Sent once the surrounding transaction has committed, so an attempt
  # that rolls back (and is retried) reports nothing and a retry does not report twice.
  def report_problem(error, context: {})
    ActiveRecord.after_all_transactions_commit do
      Rails.error.report(error, handled: true, severity: :error, context: context)
    end
  end

  # The locker branch of an order that has no claim (a locker-only paid order, a cash fulfilment): in its own
  # transaction with the lock waits bounded, so a rental row held elsewhere answers 500 (retried) instead of
  # pinning a web thread.
  def apply_locker_alone(order_hook, locker_ref, paid_at: nil)
    ApplicationRecord.own_transaction("orders_locker") { apply_locker_order(order_hook, locker_ref, paid_at: paid_at) }
  end

  # Claims the order and applies its branches (locker, membership, CC credit) in one transaction with the lock
  # waits bounded (own_transaction), so a concurrent delivery of the same order waits on the claim for at most
  # the bound, then finds it applied. Each branch runs in its own savepoint (apply_branch):
  #   * a transient failure (TRANSIENT_ERRORS: connection loss, lock timeout, query cancel, deadlock,
  #     serialization failure, a Shopify lookup error) rolls back the whole transaction, claim included, and
  #     answers 500, so Shopify retries;
  #   * any other error in a branch is permanent: that branch's writes roll back alone, it is reported, and the
  #     other branches and the claim commit.
  # The CC claim mail and every report go out after the commit, so a rolled-back attempt sends neither.
  def apply_claimed_order(plan)
    hook = plan.hook
    ApplicationRecord.own_transaction("orders_paid") do
      next unless ProcessedOrder.claim!(provider: SHOP_PROVIDER, ref: plan.id, topic: "orders/paid", name: hook["name"])

      apply_branch(plan, "locker") { apply_locker_order(hook, plan.locker_ref) } if plan.locker?
      apply_branch(plan, "membership") { apply_membership(plan) } if plan.membership?
      apply_branch(plan, "cc") { apply_cc_money(plan) } if plan.cc_items.any?
    end
  end

  # One branch in its own savepoint. Anything but a transient error is permanent: the branch rolls back alone
  # and is reported with the order id, branch and error (class, and the message unless it may carry SQL values).
  def apply_branch(plan, branch)
    ProcessedOrder.transaction(requires_new: true) { yield }
  rescue *TRANSIENT_ERRORS
    raise
  rescue StandardError => e
    detail = e.is_a?(ActiveRecord::RecordInvalid) ? e.record&.errors&.full_messages.to_a.to_sentence : e.message
    detail = "" if e.is_a?(ActiveRecord::StatementInvalid)
    report_problem(
      BranchRejected.new("#{branch} branch of order #{plan.id} rejected: #{e.class} #{detail}".strip),
      context: { shopify_order_id: plan.id, branch: branch, error_class: e.class.name }
    )
  end

  # An order without an id cannot be claimed, so neither branch is applied (the locker branch is not affected);
  # it is reported with ids only and staff reconcile it by hand. Shopify always sends the id.
  def report_order_without_id(plan)
    report_problem(
      OrderWithoutId.new("paid order without an order id; membership and CC money branches skipped"),
      context: { membership_id: plan.membership_ref, draft_order_id: plan.hook["draft_order_id"] }.compact
    )
  end

  # A membership or CC order whose target cannot be found, which no retry can fix: reported with the order id
  # and left to staff. The claim still commits.
  def report_unresolved(plan, error_class, branch, message)
    report_problem(error_class.new("#{branch} order #{plan.id} #{message}"), context: { shopify_order_id: plan.id })
  end

  def apply_membership(plan)
    if plan.hook["line_items"].blank?
      report_unresolved(plan, UnresolvedMembershipOrder, "membership", "has no line items")
      return
    end

    if plan.membership_ref.present?
      membership = Membership.find_by(id: plan.membership_ref)
      if membership
        membership.update!(status: :paid)
      else
        report_unresolved(plan, UnknownMembership, "membership", "references unknown membership #{plan.membership_ref}")
      end
      return
    end

    apply_membership_by_email(plan)
  end

  # Fallback when the order carries no membership reference: the customer's email names the user (users.email is
  # case-insensitive) and each line item's title the tier (checkout sells one membership per line, quantity 1).
  # Each matched tier line is a new membership with the current dates.
  def apply_membership_by_email(plan)
    if plan.email.blank?
      report_unresolved(plan, UnresolvedMembershipOrder, "membership", "has no membership reference and no customer email")
      return
    end

    Rails.logger.info "Membership metafield ID not found in DB, fallback to email: #{plan.email}"
    user = User.find_by(email: plan.email)
    unless user
      report_unresolved(plan, UnresolvedMembershipOrder, "membership", "has no membership reference and its customer is not a user")
      return
    end

    applied = 0
    Array.wrap(plan.hook["line_items"]).each do |item|
      title = item.is_a?(Hash) ? item["title"].to_s.strip : ""
      tier = MembershipTier.where("LOWER(title_en) = ? OR LOWER(title_fr) = ?", title.downcase, title.downcase).first
      next unless tier

      Membership.create!(user: user, membership_tier: tier, status: :paid)
      applied += 1
    end
    return if applied.positive?

    report_unresolved(plan, UnresolvedMembershipOrder, "membership", "has no membership reference and no line item names a tier")
  end

  # One CC row per CC product line item, in the claim transaction.
  def apply_cc_money(plan)
    if plan.email.blank?
      report_unresolved(plan, UnresolvedCcOrder, "CC", "has the CC product but no customer email")
      return
    end

    user = User.find_by(email: plan.email)
    plan.cc_items.each do |item|
      cc = 10 * item["quantity"].to_i
      if user.present?
        CcMoney.create!(user_id: user.id, cc: cc)
      else
        new_cc = CcMoney.create!(cc: cc, linked: false)
        hash = Rails.application.message_verifier(:cc).generate(new_cc.id)
        email = plan.email
        # Active Job here enqueues at once (enqueue_after_transaction_commit is false), so the mail is queued
        # after the claim's transaction commits; nothing is sent for a rolled-back one.
        ActiveRecord.after_all_transactions_commit { MsrMailer.send_cc_money_email(email, cc, hash).deliver_later }
      end
    end
  end
end
