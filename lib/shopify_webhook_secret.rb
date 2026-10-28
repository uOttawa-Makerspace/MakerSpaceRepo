# frozen_string_literal: true

# Resolves the secret used to verify Shopify webhook HMAC signatures.
#
# Fails closed WITHOUT taking the site down: outside test/development a missing
# credential resolves to nil (never to a guessable string), the app still boots,
# and CustomWebhooksController refuses every webhook with 503 until the secret
# is configured (see CustomWebhooksController#require_webhook_secret!).
# The "test_secret" fallback exists for test and development only.
module ShopifyWebhookSecret
  FALLBACK = "test_secret"
  class MissingSecret < StandardError; end

  FALLBACK_ENVS = %w[test development].freeze

  # Returns the secret to configure, or nil when none is available and the
  # environment may not use the public fallback.
  def self.resolve(env:, credential:)
    return credential if credential.present?

    FALLBACK_ENVS.include?(env.to_s) ? FALLBACK : nil
  end

  def self.configured?(secret)
    secret.present?
  end
end
