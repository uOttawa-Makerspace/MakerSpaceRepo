class ShopifyWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  require 'openssl'
  require 'base64'
  require 'digest'

  def response
    hmac = request.env['HTTP_X_SHOPIFY_HMAC_SHA256']
    request.body.rewind
    data = request.body.read
    webhook_ok = verify_webhook(hmac, data)

    if webhook_ok
      puts(data)
      head :no_content
    else
      head 403
    end
  end

  private

  def verify_webhook(hmac, data)
    digest = OpenSSL::Digest.new('sha256')
    calculated_hmac = Base64.encode64(OpenSSL::HMAC.digest(digest, Rails.application.secrets.shopify_webhook, data)).strip

    ActiveSupport::SecurityUtils.secure_compare(hmac, calculated_hmac)
  end

end
