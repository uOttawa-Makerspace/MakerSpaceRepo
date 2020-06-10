class CustomWebhooksController < ApplicationController
  include ShopifyApp::WebhookVerification

  def orders_paid
    params.permit!
    10.times{puts "passing HERE"}
    discount_code_params = webhook_params.to_h
    p discount_code_params['discount_codes']
    if discount_code_params['discount_codes'].present?
      shopify_discount_code_id = discount_code_params['discount_codes']['id']
      discount_code = DiscountCode.find_by_id(shopify_discount_code_id)
      discount_code.update_attributes(usage_count: 1) if discount_code
    end
    head :ok
  end

  private

  def webhook_params
    params.except(:controller, :action, :type)
  end
end