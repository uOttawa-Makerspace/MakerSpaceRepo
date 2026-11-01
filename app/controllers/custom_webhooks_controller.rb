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

  # Two phases, so the money branches (locker activation, membership paid, CC credit) apply all
  # together or not at all with respect to Shopify trouble:
  #   1. resolve every draft-order metafield reference. This is the only part that can reach Shopify,
  #      and so the only part that can raise ShopifyContext::NotConfigured; nothing is written yet.
  #   2. apply the branches (plain DB writes, plus the CC mail).
  # NotConfigured in phase 1 answers 503 with nothing applied, so Shopify retries once the config is fixed.
  # Phase 2 is NOT wrapped in one DB transaction (the CC branch sends mail with deliver_now, which a
  # rollback could not unsend); a failure inside it is a 500 and the retry re-applies the branches,
  # which is what they did before.
  def orders_paid
    order_hook = webhook_params.to_h

    locker_ref = nil
    membership_ref = nil
    begin
      locker_ref = locker_reference(order_hook) if LockerRental.draft_order_processable?(order_hook["tags"])
      membership_ref = membership_reference(order_hook) if Membership.draft_order_processable?(order_hook["tags"])
    rescue ShopifyContext::NotConfigured => e
      Rails.logger.warn("[orders_paid] Shopify not configured, answering 503 (Shopify will retry): #{e.class}")
      return head :service_unavailable
    end

    # handle lockers
    process_locker_hook(locker_ref) if LockerRental.draft_order_processable?(order_hook["tags"])

    # handle memberships
    process_membership_hook(order_hook, membership_ref) if Membership.draft_order_processable?(order_hook["tags"])
    
    # Job-order payment is recorded by staff, not automatically. Leave a trace so a
    # paid job-order draft order can be reconciled by hand.
    if JobOrder.draft_order_processable?(order_hook["tags"])
      Rails.logger.info(
        "[orders_paid] paid job-order draft order ignored (no automatic payment recording): " \
        "order id=#{order_hook['id'].inspect} name=#{order_hook['name'].inspect} " \
        "draft_order_id=#{order_hook['draft_order_id'].inspect}"
      )
    end

    # CC Money credit handling
    customer_email = order_hook.dig("customer", "email")
    if order_hook["line_items"].present? && customer_email.present?
      order_hook["line_items"].each do |item|
        increment_cc_money(item, customer_email)
      end
    end

    head :ok
  end

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

  def process_locker_hook(locker_id)
    return unless locker_id.present?

    LockerRental.find_by(id: locker_id)&.auto_assign
  end

  def process_membership_hook(order_hook, membership_id)
    return unless order_hook["line_items"].present?

    if membership_id.present?
      Membership.find_by(id: membership_id)&.update(status: :paid)
      return
    end

    # fallback if not found
    customer_email = order_hook.dig("customer", "email")
    return unless customer_email.present?

    Rails.logger.info "Membership metafield ID not found in DB, fallback to email: #{customer_email}"
    user = User.find_by(email: customer_email)
    return unless user

    order_hook["line_items"].each do |item|
      title = item["title"].to_s.strip

      membership_tier = MembershipTier.where(
        "LOWER(title_en) = ? OR LOWER(title_fr) = ?",
        title.downcase, title.downcase
      ).first

      next unless membership_tier

      Membership.create!(
        user: user,
        membership_tier: membership_tier,
        status: :paid
      )
    end
  end
  
  def increment_cc_money(product_params, email)
    return unless email.present?
    return unless product_params["product_id"].to_i == 4_359_597_129_784

    cc = 10 * product_params["quantity"].to_i
    user = User.find_by(email: email)

    if user.present?
      CcMoney.create(user_id: user.id, cc: cc)
    else
      new_cc = CcMoney.create(cc: cc, linked: false)
      hash = Rails.application.message_verifier(:cc).generate(new_cc.id)
      MsrMailer.send_cc_money_email(email, cc, hash).deliver_now
    end
  end
end