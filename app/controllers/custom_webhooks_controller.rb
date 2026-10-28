# frozen_string_literal: true

# Shopify webhooks
class CustomWebhooksController < ApplicationController
  # HMAC verification (X-Shopify-Hmac-Sha256) is on in every environment, test included,
  # so specs sign their payloads and can detect its removal. Only development is exempt
  # so unsigned webhooks can be replayed locally (e.g. with curl) without the secret.
  #
  # Fail closed when no webhook secret is configured (production/staging without the
  # credential): the app boots, but every request is refused with 503 and reported.
  # 503 (not 401) because it is OUR misconfiguration, and Shopify retries non-2xx
  # webhooks, so deliveries are processed once the secret is set. This runs before the
  # gem's HMAC check (declared first).
  before_action :require_webhook_secret!, unless: -> { Rails.env.development? }
  # A request with no X-Shopify-Hmac-Sha256 header would make the gem's secure_compare(nil, ..)
  # raise (500); answer 401 before the gem's check instead.
  before_action :require_hmac_header!, unless: -> { Rails.env.development? }
  include ShopifyApp::WebhookVerification unless Rails.env.development?
  include ShopifyConcern

  def orders_paid
    order_hook = webhook_params.to_h

    # handle lockers
    if LockerRental.draft_order_processable?(order_hook["tags"])
      process_locker_hook(order_hook)
    end
    
    # handle memberships
    if Membership.draft_order_processable?(order_hook["tags"])
      process_membership_hook(order_hook)
    end
    
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

  def require_webhook_secret!
    return if ShopifyWebhookSecret.configured?(ShopifyApp.configuration.secret) ||
              ShopifyWebhookSecret.configured?(ShopifyApp.configuration.old_secret)

    error = ShopifyWebhookSecret::MissingSecret.new(
      "Shopify webhook secret is not configured (credentials.#{Rails.env}.shopify.webhook); refusing webhook"
    )
    Rails.error.report(error, handled: true, severity: :error, context: { path: request.path })
    Airbrake.notify(error) if defined?(Airbrake) && Airbrake.configured?
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

  def process_locker_hook(order_hook)
    gid = draft_order_gid_from_hook(order_hook)

    locker_id_metafield = order_hook['metafields']&.find do |m|
      m['namespace'] == 'makerepo' && m['key'] == 'locker_db_reference'
    end

    locker_id_metafield ||= draft_order_metafields(gid)&.find do |field|
      field["key"] == "locker_db_reference"
    end

    return unless locker_id_metafield&.[]("value").present?
    
    locker_rental = LockerRental.find_by(id: locker_id_metafield["value"])
    locker_rental&.auto_assign
  end

  def process_membership_hook(order_hook)
    return unless order_hook["line_items"].present?

    gid = draft_order_gid_from_hook(order_hook)

    membership_id_metafield = order_hook['metafields']&.find do |m|
      m['namespace'] == 'makerepo' && m['key'] == 'membership_db_reference'
    end

    membership_id_metafield ||= draft_order_metafields(gid)&.find do |field|
      field["key"] == "membership_db_reference"
    end

    if membership_id_metafield&.[]("value").present?
      membership = Membership.find_by(id: membership_id_metafield["value"])
      membership&.update(status: :paid)
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