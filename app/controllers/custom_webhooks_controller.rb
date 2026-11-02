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
  #   1. resolve every draft-order metafield reference. This is the only part that can reach Shopify,
  #      and so the only part that can raise ShopifyContext::NotConfigured; nothing is written yet.
  #   2. apply the branches in ONE transaction (apply_claimed_order), together with the order's claim in
  #      processed_orders.
  # NotConfigured in phase 1 answers 503 with nothing applied, so Shopify retries once the config is fixed.
  # A claimed order is an applied order, and every branch either applies or is reported: a write that fails
  # raises, which rolls the claim back and answers 500 so Shopify retries; a problem no retry can fix (the
  # order names a membership or locker rental that does not exist) is reported with the order id and the
  # claim is committed, so it is neither retried forever nor lost.
  # An order with a membership or CC branch is applied once per Shopify order (the claim, whose unique key
  # also covers a repeated delivery). A locker-only order has no claim: locker_payments, keyed by the
  # order id, is its ledger (shared with orders_fulfilled).
  def orders_paid
    order_hook = webhook_params.to_h
    tags = order_hook["tags"]
    claimable = claimable_order?(order_hook)
    ref = order_id(order_hook)

    # An order that was already claimed is applied: answer before any Shopify lookup.
    if claimable && ref.present? && ProcessedOrder.exists?(provider: SHOP_PROVIDER, provider_ref: ref.to_s)
      Rails.logger.info("[orders_paid] order #{ref} already applied, nothing to do")
      return head :ok
    end

    locker_ref = nil
    membership_ref = nil
    begin
      locker_ref = locker_reference(order_hook) if LockerRental.draft_order_processable?(tags)
      membership_ref = membership_reference(order_hook) if Membership.draft_order_processable?(tags)
    rescue ShopifyContext::NotConfigured => e
      Rails.logger.warn("[orders_paid] Shopify not configured, answering 503 (Shopify will retry): #{e.class}")
      return head :service_unavailable
    end

    # Job-order payment is recorded by staff, not automatically. Leave a trace so a
    # paid job-order draft order can be reconciled by hand.
    if JobOrder.draft_order_processable?(tags)
      Rails.logger.info(
        "[orders_paid] paid job-order draft order ignored (no automatic payment recording): " \
        "order id=#{order_hook['id'].inspect} name=#{order_hook['name'].inspect} " \
        "draft_order_id=#{order_hook['draft_order_id'].inspect}"
      )
    end

    if claimable && ref.present?
      apply_claimed_order(order_hook, ref, locker_ref, membership_ref)
    else
      apply_locker_order(order_hook, locker_ref) if LockerRental.draft_order_processable?(tags)
      report_order_without_id(order_hook, membership_ref) if claimable
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
      locker_ref = locker_reference(order_hook)
    rescue ShopifyContext::NotConfigured => e
      Rails.logger.warn("[orders_fulfilled] Shopify not configured, answering 503 (Shopify will retry): #{e.class}")
      return head :service_unavailable
    end

    # The cash was taken when the order was fulfilled, not when it was created (processed_at)
    fulfilled_at = Array(order_hook["fulfillments"]).filter_map { |f| parse_time(f["created_at"]) }.max
    apply_locker_order(order_hook, locker_ref, paid_at: fulfilled_at || Time.current)
    head :ok
  end

  # Raised only to be reported (Rails.error.report).
  class LockerOrderWithoutId < StandardError; end
  class LockerOrderWithoutReference < StandardError; end
  class UnknownLockerRental < StandardError; end
  class OrderWithoutId < StandardError; end
  class UnknownMembership < StandardError; end
  class UnresolvedMembershipOrder < StandardError; end

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

  def metafield_value(order_hook, gid, key)
    field = order_hook['metafields']&.find do |m|
      m['namespace'] == 'makerepo' && m['key'] == key
    end
    field ||= draft_order_metafields(gid)&.find { |f| f["key"] == key }
    field&.[]("value").presence
  end

  # Phase 1 (may raise NotConfigured): the DB id the locker branch will act on, or nil.
  def locker_reference(order_hook)
    metafield_value(order_hook, draft_order_gid_from_hook(order_hook), "locker_db_reference")
  end

  # Phase 1 (may raise NotConfigured): the membership id, or nil. No line items: nothing to do, no lookup.
  def membership_reference(order_hook)
    return unless order_hook["line_items"].present?

    metafield_value(order_hook, draft_order_gid_from_hook(order_hook), "membership_db_reference")
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
      Rails.error.report(
        LockerOrderWithoutReference.new("locker order #{order_id(order_hook)} carries no locker_db_reference"),
        handled: true, severity: :error, context: { shopify_order_id: order_id(order_hook) }
      )
      return
    end

    # A locker order must carry the Shopify order id (it is the idempotency key of the payment record).
    # Shopify always sends it, so a missing one is a bug on our side or theirs: skip ONLY the locker branch
    # (never answer an error for the whole order, which would be retried forever and block the membership
    # and CC branches), and report it with ids only so staff can reconcile the rental by hand.
    if order_id(order_hook).blank?
      Rails.error.report(
        LockerOrderWithoutId.new("locker order without an order id; locker branch skipped (rental #{locker_ref})"),
        handled: true, severity: :error, context: { locker_rental_id: locker_ref }
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
      Rails.error.report(
        UnknownLockerRental.new("locker order #{order_id(order_hook)} references unknown locker rental #{locker_id}"),
        handled: true, severity: :error,
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

  # The order has something to claim: a membership order (membership tag and line items) or a CC order (a line
  # item of the CC product and a customer email). Plain merch, job-order and locker-only orders have none.
  def claimable_order?(order_hook)
    (Membership.draft_order_processable?(order_hook["tags"]) && order_hook["line_items"].present?) ||
      cc_items(order_hook).any?
  end

  def cc_items(order_hook)
    return [] if order_hook.dig("customer", "email").blank?

    Array.wrap(order_hook["line_items"]).select { |item| item.is_a?(Hash) && item["product_id"].to_i == CC_PRODUCT_ID }
  end

  # Claims the order and applies all its branches (locker, membership, CC credit) in one transaction with the
  # lock waits bounded (own_transaction), so a concurrent delivery of the same order waits on the claim for at
  # most the bound, then finds it applied; a timeout or any failed write rolls everything back, answers 500, and
  # Shopify retries. The CC claim mail is queued for after the commit, so a rolled-back claim sends none.
  def apply_claimed_order(order_hook, ref, locker_ref, membership_ref)
    ProcessedOrder.own_transaction("orders_paid") do
      next unless ProcessedOrder.claim!(provider: SHOP_PROVIDER, ref: ref, topic: "orders/paid", name: order_hook["name"])

      apply_locker_order(order_hook, locker_ref) if LockerRental.draft_order_processable?(order_hook["tags"])
      if Membership.draft_order_processable?(order_hook["tags"]) && order_hook["line_items"].present?
        process_membership_hook(order_hook, membership_ref)
      end
      cc_items(order_hook).each { |item| increment_cc_money(item, order_hook.dig("customer", "email")) }
    end
  end

  # An order without an id cannot be claimed, so neither branch is applied (the locker branch is not affected);
  # it is reported with ids only and staff reconcile it by hand. Shopify always sends the id.
  def report_order_without_id(order_hook, membership_ref)
    Rails.error.report(
      OrderWithoutId.new("paid order without an order id; membership and CC money branches skipped"),
      handled: true, severity: :error,
      context: { membership_id: membership_ref, draft_order_id: order_hook["draft_order_id"] }.compact
    )
  end

  # A membership order whose target cannot be found, which no retry can fix: reported with the order id and
  # left to staff. The claim still commits.
  def report_unresolved_membership(order_hook, error_class, message)
    Rails.error.report(
      error_class.new("membership order #{order_id(order_hook)} #{message}"),
      handled: true, severity: :error, context: { shopify_order_id: order_id(order_hook) }
    )
  end

  def process_membership_hook(order_hook, membership_id)
    if membership_id.present?
      membership = Membership.find_by(id: membership_id)
      if membership
        membership.update!(status: :paid)
      else
        report_unresolved_membership(order_hook, UnknownMembership, "references unknown membership #{membership_id}")
      end
      return
    end

    # fallback if not found
    customer_email = order_hook.dig("customer", "email")
    if customer_email.blank?
      report_unresolved_membership(order_hook, UnresolvedMembershipOrder, "has no membership reference and no customer email")
      return
    end

    Rails.logger.info "Membership metafield ID not found in DB, fallback to email: #{customer_email}"
    user = User.find_by(email: customer_email)
    unless user
      report_unresolved_membership(order_hook, UnresolvedMembershipOrder, "has no membership reference and its customer is not a user")
      return
    end

    created = 0
    Array.wrap(order_hook["line_items"]).each do |item|
      title = item.is_a?(Hash) ? item["title"].to_s.strip : ""

      membership_tier = MembershipTier.where(
        "LOWER(title_en) = ? OR LOWER(title_fr) = ?",
        title.downcase, title.downcase
      ).first

      next unless membership_tier

      Membership.create!(user: user, membership_tier: membership_tier, status: :paid)
      created += 1
    end
    report_unresolved_membership(order_hook, UnresolvedMembershipOrder, "has no membership reference and no line item names a tier") if created.zero?
  end

  # Runs inside the claim transaction, for a CC product line item of an order with a customer email.
  def increment_cc_money(product_params, email)
    cc = 10 * product_params["quantity"].to_i
    user = User.find_by(email: email)

    if user.present?
      CcMoney.create!(user_id: user.id, cc: cc)
    else
      new_cc = CcMoney.create!(cc: cc, linked: false)
      hash = Rails.application.message_verifier(:cc).generate(new_cc.id)
      # Active Job here enqueues at once (enqueue_after_transaction_commit is false), so the mail is queued
      # after the claim's transaction commits; nothing is sent for a rolled-back one.
      ActiveRecord.after_all_transactions_commit { MsrMailer.send_cc_money_email(email, cc, hash).deliver_later }
    end
  end
end
