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

  # Both order webhooks are an inbox: the verified body is stored (ProcessedOrder) and ApplyProcessedOrderJob applies
  # it, so the webhook itself never calls Shopify and never touches memberships, CC Money or lockers, and answers
  # fast. A delivery of an order already stored inserts nothing and changes nothing: the stored order's own schedule
  # (ProcessedOrder.dispatch_due) decides when it is applied.
  # An order with nothing to apply (plain merch, job orders) is answered and not stored.
  def orders_paid
    hook = verified_body
    # Job-order payment is recorded by staff, not automatically. Leave a trace so a
    # paid job-order draft order can be reconciled by hand.
    if JobOrder.draft_order_processable?(hook["tags"])
      Rails.logger.info(
        "[orders_paid] paid job-order draft order ignored (no automatic payment recording): " \
        "order id=#{hook['id'].inspect} name=#{hook['name'].inspect} draft_order_id=#{hook['draft_order_id'].inspect}"
      )
    end
    store_order(hook, "orders/paid")
  end

  # Cash locker payments. Staff fulfil a cash order in Shopify without marking it paid, so the fulfillment
  # is the payment event. Only the locker branch runs, and only while Shopify still shows the payment as
  # pending: a paid order is handled by orders_paid, and a refunded, voided or partly paid one is not a
  # cash payment. It is its own stored unit (provider_ref "<id>/fulfilled"), so a later orders_paid of the same
  # order still applies its memberships and CC Money; the locker payment record is keyed by the Shopify order id,
  # so the two never apply a locker twice. Memberships and CC Money paid in cash stay with staff.
  def orders_fulfilled
    hook = verified_body
    return head :ok unless hook["financial_status"] == "pending"

    store_order(hook, "orders/fulfilled")
  end

  # Raised only to be reported (Rails.error.report).
  class OrderWithoutId < StandardError; end

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

  # The verified webhook body, as received (a JSON object; anything else is an empty one).
  def verified_body
    body = JSON.parse(request.raw_post)
    body.is_a?(Hash) ? body : {}
  rescue JSON::ParserError
    {}
  end

  def store_order(hook, topic)
    plan = ShopOrderApplier.plan_for(hook, topic: topic)
    return head :ok unless plan.branches?

    if plan.id.blank?
      # Shopify always sends the id (the key of the stored order); reported with ids only, staff reconcile it.
      Rails.error.report(
        OrderWithoutId.new("#{topic} order without an order id; nothing stored"),
        handled: true, severity: :error, context: { draft_order_id: hook["draft_order_id"] }.compact
      )
      return head :ok
    end

    order, = ProcessedOrder.receive!(provider: ShopOrderApplier::PROVIDER, order_id: plan.id, topic: topic,
                                     payload: hook, name: hook["name"])
    # The row is durable and due now: it is handed to the queue here, and if that fails (answer 200 all the same)
    # the recurring dispatcher hands it out. A redelivery of an order that is already scheduled, applied or failed
    # hands out nothing.
    ProcessedOrder.dispatch_due(id: order.id)
    head :ok
  end
end
