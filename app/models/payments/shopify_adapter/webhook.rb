# frozen_string_literal: true

module Payments
  class ShopifyAdapter
    # Turns one Shopify order webhook into a PaymentEvent (read by Order), or raises WebhookRejected.
    #
    # `body` is the raw request body and `headers` the request's headers (read by their Rack names, e.g.
    # HTTP_X_SHOPIFY_HMAC_SHA256). Verification (#verify!, what CustomWebhooksController runs before every webhook):
    # the X-Shopify-Hmac-Sha256 header must be the Base64 HMAC-SHA256 of the raw body under the secret or the old
    # secret, the check the shopify_app gem's webhook verification made. The topic comes from the X-Shopify-Topic
    # header. A body that is not a JSON object, or an order without an id, is :malformed.
    class Webhook
      HMAC_HEADER = "HTTP_X_SHOPIFY_HMAC_SHA256"
      TOPIC_HEADER = "HTTP_X_SHOPIFY_TOPIC"
      TOPICS = %w[orders/paid orders/fulfilled orders/cancelled].freeze

      def initialize(body:, headers:, secrets:)
        @raw_body = body.to_s
        @headers = headers
        @secrets = Array(secrets).select(&:present?)
      end

      def event
        verify!
        topic = @headers[TOPIC_HEADER]
        raise WebhookRejected, :unsupported_topic unless TOPICS.include?(topic)

        event = Order.new(body, topic: topic).event
        raise WebhookRejected, :malformed if event.provider_ref.blank?

        event
      end

      # Raises WebhookRejected (:not_configured, :unsigned, :bad_signature) unless the body is signed by Shopify.
      def verify!
        raise WebhookRejected, :not_configured if @secrets.empty?

        hmac = @headers[HMAC_HEADER]
        raise WebhookRejected, :unsigned if hmac.blank?
        raise WebhookRejected, :bad_signature unless @secrets.any? { |secret| signed_with?(hmac, secret) }
      end

      private

      def signed_with?(hmac, secret)
        expected = Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, @raw_body))
        ActiveSupport::SecurityUtils.secure_compare(hmac, expected)
      end

      def body
        hook = JSON.parse(@raw_body)
        raise WebhookRejected, :malformed unless hook.is_a?(Hash)

        hook
      rescue JSON::ParserError
        raise WebhookRejected, :malformed
      end
    end
  end
end
