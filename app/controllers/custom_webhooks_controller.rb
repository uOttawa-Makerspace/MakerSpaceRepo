# frozen_string_literal: true

# Shopify webhooks
class CustomWebhooksController < ApplicationController
  include ShopifyApp::WebhookVerification unless Rails.env.test? || Rails.env.development?
  include ShopifyConcern

  def orders_paid
    # We now handle whitelisting in the webhook_params method below.

    # This is a locker marked as paid. We use the tags to determine which model
    # reads the webhook.
    # Note: webhook_params is now a safe Hash thanks to Strong Parameters.
    order_hook = webhook_params.to_h

    # handle lockers
    if LockerRental.draft_order_processable? order_hook["tags"]
      process_locker_hook(order_hook)
    end
    
    # handle memberships
    if Membership.draft_order_processable? order_hook["tags"]
      process_membership_hook(order_hook)
    end
    
    # handle job orders
    if JobOrder.draft_order_processable? order_hook["tags"]
      process_job_orders_hook(order_hook)
    end

    # REVIEW: Old code. No clue if this works still
    discount_code_params = webhook_params.to_h
    if discount_code_params["discount_codes"].present?
      shopify_discount_code = discount_code_params["discount_codes"][0]["code"]
      discount_code = DiscountCode.find_by(code: shopify_discount_code)
      discount_code&.update(usage_count: 1)
    end

    if discount_code_params["line_items"].present?
      discount_code_params["line_items"].each do |item|
        increment_cc_money(item, discount_code_params["customer"]["email"])
      end
    end

    head :ok
  end

  private

  # Explicitly define the keys we expect from Shopify
  def webhook_params
    params.permit!
    # NOTE: This doesn't let tags through.
    # params.permit(
    #   :id,
    #   :tags,
    #   :admin_graphql_api_id,
    #   :email,
    #   # Allow tags to be an array (common in tests) or scalar
    #   tags: [],
    #   # Allow array of hashes for metafields with common keys
    #   metafields: [:namespace, :key, :value, :value_type, :description, :id],
    #   # Allow array of hashes for discount codes
    #   discount_codes: [:code, :amount, :type],
    #   # Allow array of hashes for line items with standard fields
    #   line_items: [:product_id, :quantity, :title, :variant_id, :sku, :price, :name],
    #   # Allow specific keys for customer
    #   customer: [:id, :email, :first_name, :last_name]
    # )
  end

  def process_locker_hook(order_hook)
    # get order ID from metafields
    locker_id_metafield = order_hook['metafields']&.find do |m|
      m['namespace'] == 'makerepo' && m['key'] == 'locker_db_reference'
    end

    # Because the webhook doesn't return the metafield (last I checked, at
    # least), we fetch it with a second call to get ID of the DB record
    locker_id_metafield ||=
      draft_order_metafields(order_hook["admin_graphql_api_id"])&.find do |field|
        field["key"] == "locker_db_reference"
      end
    
    locker_rental = LockerRental.find(locker_id_metafield["value"])
    # state change, auto assign, and sends mail
    locker_rental.auto_assign if locker_rental.present?
  end

  # membership handler
  def process_membership_hook(order_hook)
    return unless order_hook["line_items"].present? && order_hook["customer"].present?

    # find membership in db
    membership_id_metafield = order_hook['metafields']&.find do |m|
      m['namespace'] == 'makerepo' && m['key'] == 'membership_db_reference'
    end

    membership_id_metafield ||=
      draft_order_metafields(order_hook["admin_graphql_api_id"])&.find do |field|
        field["key"] == "membership_db_reference"
      end

    if membership_id_metafield
      membership = Membership.find_by(id: membership_id_metafield["value"])
      membership&.update(status: :paid)
      return
    end

    # fallback if not found
    Rails.logger.info "Membership metafield ID not found in DB, fallback to email"
    user = User.find_by(email: order_hook["customer"]["email"])
    return unless user

    order_hook["line_items"].each do |item|
      title = item["title"].to_s.strip

      membership_tier =
        MembershipTier.where("LOWER(title_en) = ? OR LOWER(title_fr) = ?", title.downcase, title.downcase).first

      next unless membership_tier

      Membership.create!(
        user: user,
        membership_tier: membership_tier,
        status: :paid
      )
    end
  end
  
  # job order handler
  def process_job_orders_hook(order_hook)
    return unless order_hook["line_items"].present? && order_hook["customer"].present?

    # find jo in db
    job_order_id_metafield = order_hook['metafields']&.find do |m|
      m['namespace'] == 'makerepo' && m['key'] == 'job_order_db_reference'
    end

    job_order_id_metafield ||=
      draft_order_metafields(order_hook["admin_graphql_api_id"])&.find do |field|
        field["key"] == "job_order_db_reference"
      end

    return unless job_order_id_metafield
      
    job_order = JobOrder.find_by(id: job_order_id_metafield["value"])
    job_order.update_status(true, JobStatus::COMPLETED, JobStatus::PAID, false)
  end

  def increment_cc_money(product_params, email)
    return unless product_params["product_id"].to_i == 4_359_597_129_784
    cc = 10 * product_params["quantity"].to_i
    if User.find_by_email(email).present?
      CcMoney.create(user_id: User.find_by_email(email).id, cc: cc)
    else
      new_cc = CcMoney.create(cc: cc, linked: false)
      hash = Rails.application.message_verifier(:cc).generate(new_cc.id)
      MsrMailer.send_cc_money_email(email, cc, hash).deliver_now
    end
  end
end
