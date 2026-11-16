# frozen_string_literal: true

module Payments
  # Raised by an adapter's #parse_webhook for a request it does not accept. `reason` says why:
  #   :not_configured   no webhook secret is configured (our misconfiguration)
  #   :unsigned         the request carries no signature
  #   :bad_signature    the signature does not match the body
  #   :unsupported_topic the notice is not one the adapter turns into a payment
  #   :malformed        the body is not a payment notice (not a JSON object, or no order id)
  class WebhookRejected < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super("payment webhook rejected (#{reason})")
    end
  end
end
