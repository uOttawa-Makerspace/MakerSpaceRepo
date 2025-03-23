# frozen_string_literal: true

# Shopify webhooks
class CustomWebhooksController < ApplicationController
  include ShopifyApp::WebhookVerification unless Rails.env.test?

  def orders_paid
    params.permit!
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

  def draft_orders_update
    params.permit!
    draft_order = webhook_params.to_h

    Rails.logger.debug draft_order if Rails.env.to_sym == :staging

    process_locker_hook(draft_order) if draft_order['tags'].include? "MakerepoLocker"

    head :ok
  end

  private

  def webhook_params
    params.except(:controller, :action, :type)
  end

  def process_locker_hook(draft_order)
    # get order ID from metafields
    draft_order['metafields']['makerepo']
    locker_rental =
        LockerRental.find(
          event.data.object.client_reference_id.gsub("locker-rental-", "")
        )
      # state change, auto assign, and sends mail
      locker_rental.auto_assign if locker_rental.present?
  end

  def increment_cc_money(product_params, email)
    if product_params["product_id"].to_i == 4_359_597_129_784
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
end
