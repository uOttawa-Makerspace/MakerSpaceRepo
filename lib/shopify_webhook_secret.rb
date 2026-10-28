# frozen_string_literal: true

# Resolves the secret used to verify Shopify webhook HMAC signatures.
#
# Fails closed: in production and staging a missing credential raises at boot
# instead of silently falling back to a publicly known string (which would let
# anyone forge signed webhooks: free memberships, CC Money, locker activation).
# The "test_secret" fallback exists for test and development only.
module ShopifyWebhookSecret
  FALLBACK = "test_secret"
  FAIL_CLOSED_ENVS = %w[production staging].freeze

  class MissingSecret < StandardError; end

  def self.resolve(env:, credential:)
    return credential if credential.present?

    if FAIL_CLOSED_ENVS.include?(env.to_s)
      raise MissingSecret,
            "Shopify webhook secret is missing: set credentials.#{env}.shopify.webhook. " \
            "Refusing to boot with a guessable fallback secret in #{env}."
    end

    FALLBACK
  end
end
