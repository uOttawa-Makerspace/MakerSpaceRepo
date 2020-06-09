class ShopifyWebhooksControllerController < ApplicationController
  require 'openssl'
  require 'base64'

  def response
    request.body.rewind
    data = request.body.read
    verified = verify_webhook(data, env["HTTP_X_SHOPIFY_HMAC_SHA256"])

    # Output 'true' or 'false'
    puts "Webhook verified: #{verified}"
    head :ok
  end

  def verify_webhook(data, hmac_header)
    calculated_hmac = Base64.strict_encode64(OpenSSL::HMAC.digest('sha256', Rails.application.secrets.shopify_webhook, data))
    ActiveSupport::SecurityUtils.secure_compare(calculated_hmac, hmac_header)
  end
end
