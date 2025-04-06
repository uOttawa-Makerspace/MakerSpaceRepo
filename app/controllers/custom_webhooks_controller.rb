# frozen_string_literal: true

# Shopify webhooks
class CustomWebhooksController < ApplicationController
  include ShopifyApp::WebhookVerification unless Rails.env.test? || Rails.env.development?

  def orders_paid
    params.permit!

    # This is a locker marked as paid
    order_hook = webhook_params.to_h

    # get order ID from metafields
    locker_id_metafield = order_hook['metafields']&.find do |m|
      m['namespace'] == 'makerepo' && m['key'] == 'locker_db_reference'
    end

    # Filter out staging/production tags
    unless locker_id_metafield.nil? || !order_hook['tags']&.include?(ShopifyConcern.target_tag)
      process_locker_hook(locker_id_metafield['value'])
    end

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

  def webhook_params
    params.except(:controller, :action, :type)
  end

  def process_locker_hook(locker_id)
    locker_rental = LockerRental.find(locker_id)
    # state change, auto assign, and sends mail
    locker_rental.auto_assign if locker_rental.present?
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
