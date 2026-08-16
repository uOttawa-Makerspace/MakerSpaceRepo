# frozen_string_literal: true

# Shopify webhooks
class CustomWebhooksController < ApplicationController
  include ShopifyApp::WebhookVerification unless Rails.env.test? || Rails.env.development?
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
    
    # handle job orders
    if JobOrder.draft_order_processable?(order_hook["tags"])
      process_job_orders_hook(order_hook)
    end

    # Discount codes handling
    if order_hook["discount_codes"].present?
      shopify_discount_code = order_hook["discount_codes"][0]["code"]
      discount_code = DiscountCode.find_by(code: shopify_discount_code)
      discount_code&.update(usage_count: (discount_code.usage_count.to_i + 1))
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
  
  def process_job_orders_hook(order_hook)
    return unless order_hook["line_items"].present?

    gid = draft_order_gid_from_hook(order_hook)

    job_order_id_metafield = order_hook['metafields']&.find do |m|
      m['namespace'] == 'makerepo' && m['key'] == 'job_order_db_reference'
    end

    job_order_id_metafield ||= draft_order_metafields(gid)&.find do |field|
      field["key"] == "job_order_db_reference"
    end

    return unless job_order_id_metafield&.[]("value").present?
      
    job_order = JobOrder.find_by(id: job_order_id_metafield["value"])
    job_order&.update_status(true, JobStatus::COMPLETED, JobStatus::PAID, false)
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