class CustomWebhooksController < ApplicationController
  include ShopifyApp::WebhookVerification

  def orders_paid
    params.permit!
    # SomeJob.perform_later(shop_domain: shop_domain, webhook: webhook_params.to_h)
    10.times{puts "passing HERE"}
    discount_code_params = webhook_params.to_h
    shopify_discount_code_id = discount_code_params['discount_code']['id']
    discount_code = DiscountCode.find_by_id(shopify_discount_code_id)
    discount_code.update_attributes(usage_count: 1) if discount_code
    head :no_content
  end

  private

  def webhook_params
    params.except(:controller, :action, :type)
  end
end