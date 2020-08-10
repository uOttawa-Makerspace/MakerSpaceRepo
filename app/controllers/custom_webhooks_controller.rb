# frozen_string_literal: true

class CustomWebhooksController < ApplicationController
  include ShopifyApp::WebhookVerification unless Rails.env == 'test'

  def orders_paid
    params.permit!
    discount_code_params = webhook_params.to_h
    puts(discount_code_params['line_items'])
    if discount_code_params['discount_codes'].present?
      shopify_discount_code = discount_code_params['discount_codes'][0]['code']
      discount_code = DiscountCode.find_by(code: shopify_discount_code)
      discount_code&.update(usage_count: 1)
    end

    if discount_code_params['line_items'].present?
      discount_code_params['line_items'].each do |item|
        if item['product_id'] == 4359597129784
          cc = 10*item['quantity']
          CcMoney.create(user_id: User.find_by_email(discount_code_params['customer']['email']).id, cc: cc)
        end
      end
    end

    head :ok
  end

  private

  def webhook_params
    params.except(:controller, :action, :type)
  end
end
