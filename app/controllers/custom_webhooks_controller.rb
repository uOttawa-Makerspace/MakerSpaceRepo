class CustomWebhooksController < ApplicationController
  include ShopifyApp::WebhookVerification

  def orders_paid
    params.permit!
    discount_code_params = webhook_params.to_h
    if discount_code_params['discount_codes'].present?
      shopify_discount_code = discount_code_params['discount_codes'][0]['code']
      discount_code = DiscountCode.find_by(code: shopify_discount_code)
      discount_code.update_attributes(usage_count: 1) if discount_code
    end
    head :ok
  end

  private

  def webhook_params
    params.except(:controller, :action, :type)
  end
end