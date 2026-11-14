# frozen_string_literal: true

module Payments
  class ShopifyAdapter
    # Turns one Shopify order webhook into a PaymentEvent, or raises WebhookRejected.
    #
    # Verification is the check CustomWebhooksController runs today (ShopifyApp::WebhookVerification): the
    # X-Shopify-Hmac-Sha256 header must be the Base64 HMAC-SHA256 of the raw body under the secret or the old secret.
    # The topic comes from the X-Shopify-Topic header. provider_ref is the key ProcessedOrder stores the order under
    # (the order id; "<id>/fulfilled" for an orders/fulfilled delivery). The reference is read from the order's tags:
    # the kind from this environment's operating tag, the record id from the marker tag (lockers and job orders;
    # a membership's id is only in the draft's metafields, so it is nil here) and the checkout id from the checkout tag.
    class Webhook
      HMAC_HEADER = "HTTP_X_SHOPIFY_HMAC_SHA256"
      TOPIC_HEADER = "HTTP_X_SHOPIFY_TOPIC"
      TOPICS = %w[orders/paid orders/fulfilled].freeze

      # A draft's or order's tags as a list of stripped strings, whether Shopify sent an array or a comma-separated string.
      def self.tag_list(tags)
        list = tags.is_a?(String) ? tags.split(",") : Array(tags)
        list.map { |t| t.to_s.strip }
      end

      def initialize(request, secrets:)
        @request = request
        @secrets = Array(secrets).select(&:present?)
      end

      def event
        verify!
        topic = @request.headers[TOPIC_HEADER]
        raise WebhookRejected, :unsupported_topic unless TOPICS.include?(topic)

        hook = body
        order_id = ShopOrderApplier.order_id(hook)
        raise WebhookRejected, :malformed if order_id.blank?

        PaymentEvent.new(provider: PROVIDER, provider_ref: ProcessedOrder.ref_for(order_id, topic),
                         reference: reference(self.class.tag_list(hook["tags"])),
                         amount: amount(hook["total_price"]), paid_at: paid_at(hook, topic))
      end

      private

      def verify!
        raise WebhookRejected, :not_configured if @secrets.empty?

        hmac = @request.headers[HMAC_HEADER]
        raise WebhookRejected, :unsigned if hmac.blank?
        raise WebhookRejected, :bad_signature unless @secrets.any? { |secret| signed_with?(hmac, secret) }
      end

      def signed_with?(hmac, secret)
        expected = Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, @request.raw_post))
        ActiveSupport::SecurityUtils.secure_compare(hmac, expected)
      end

      def body
        hook = JSON.parse(@request.raw_post)
        raise WebhookRejected, :malformed unless hook.is_a?(Hash)

        hook
      rescue JSON::ParserError
        raise WebhookRejected, :malformed
      end

      def reference(tags)
        kind = KINDS.find { |k| tags.include?("#{ShopifyConcern.target_tag}_#{k}") }
        return nil unless kind

        Reference.new(kind: kind, record_id: MARKERS[kind] && tagged_id(tags, "#{MARKERS[kind]}:"),
                      checkout_id: tagged_id(tags, ShopifyAdapter.checkout_tag("")))
      end

      # The id after `prefix` in the tags: nil when no tag or two different ones carry it.
      def tagged_id(tags, prefix)
        pattern = /\A#{Regexp.escape(prefix)}(\d+)\z/
        ids = tags.filter_map { |t| pattern.match(t)&.captures&.first&.to_i }.uniq
        ids.first if ids.one?
      end

      def amount(value)
        parsed = BigDecimal(value.to_s.strip, exception: false)
        parsed.round(2) if parsed&.finite?
      end

      # orders/fulfilled: when the cash was taken (the latest fulfillment); orders/paid: the order's processed_at.
      def paid_at(hook, topic)
        time = if topic == "orders/fulfilled"
                 Array(hook["fulfillments"]).filter_map { |f| ShopOrderApplier.parse_time(f["created_at"]) if f.is_a?(Hash) }.max
               else
                 ShopOrderApplier.parse_time(hook["processed_at"])
               end
        time || Time.current
      end
    end
  end
end
