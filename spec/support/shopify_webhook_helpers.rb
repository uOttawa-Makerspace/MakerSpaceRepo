# frozen_string_literal: true

# Signs Shopify webhook bodies exactly as ShopifyApp::PayloadVerification
# (shopify_app gem, lib/shopify_app/controller_concerns/payload_verification.rb)
# verifies them:
#
#   header  X-Shopify-Hmac-Sha256   (read as HTTP_X_SHOPIFY_HMAC_SHA256)
#   value   Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, raw_body))
#   secret  ShopifyApp.configuration.secret (config/initializers/shopify_app.rb;
#           "test_secret" outside production/staging)
#
# The HMAC is over the RAW request body, so the body is serialised once here and
# sent as-is.
module ShopifyWebhookHelpers
  SHOPIFY_HMAC_HEADER = "X-Shopify-Hmac-Sha256"

  def shopify_webhook_secret
    ShopifyApp.configuration.secret
  end

  def shopify_hmac_for(body, secret: shopify_webhook_secret)
    Base64.strict_encode64(OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), secret, body))
  end

  # { "CONTENT_TYPE" => ..., "X-Shopify-Hmac-Sha256" => ... } for a raw body.
  def shopify_webhook_headers(body, secret: shopify_webhook_secret)
    { "CONTENT_TYPE" => "application/json", SHOPIFY_HMAC_HEADER => shopify_hmac_for(body, secret: secret) }
  end

  # POST a correctly signed orders_paid webhook (request specs).
  def signed_orders_paid(params = {}, secret: shopify_webhook_secret)
    body = params.to_json
    post orders_paid_custom_webhooks_path, params: body, headers: shopify_webhook_headers(body, secret: secret)
  end

  # POST an orders_paid webhook with no signature, or one computed by `hmac`.
  def unsigned_orders_paid(params = {}, hmac: nil)
    body = params.to_json
    headers = { "CONTENT_TYPE" => "application/json" }
    headers[SHOPIFY_HMAC_HEADER] = hmac if hmac
    post orders_paid_custom_webhooks_path, params: body, headers: headers
  end

  # Controller specs: sign and post as raw JSON so raw_post is the signed body.
  def signed_controller_orders_paid(params = {}, secret: shopify_webhook_secret)
    body = params.to_json
    request.headers["CONTENT_TYPE"] = "application/json"
    request.headers["HTTP_X_SHOPIFY_HMAC_SHA256"] = shopify_hmac_for(body, secret: secret)
    post :orders_paid, body: body
  end
end

RSpec.configure do |config|
  config.include ShopifyWebhookHelpers, type: :request
  config.include ShopifyWebhookHelpers, type: :controller
  config.include ShopifyWebhookHelpers, type: :system
end
