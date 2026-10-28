# frozen_string_literal: true

require Rails.root.join("lib/shopify_webhook_secret")

ShopifyApp.configure do |config|
  # Fails closed (raises at boot) in production/staging when the credential is missing;
  # the "test_secret" fallback applies to test/development only.
  config.secret = ShopifyWebhookSecret.resolve(
    env: Rails.env,
    credential: Rails.application.credentials.dig(Rails.env.to_sym, :shopify, :webhook)
  )

  # NOTE: We intentionally do NOT set config.api_key here. 
  # If api_key is present, shopify_app treats this as a public OAuth app and tries to 
  # mutate autoload paths, which crashes on Rails 8.1+ with a FrozenError.
  # Leaving it blank keeps it in "private app" mode. Our ShopifyConcern handles the 
  # actual API key and access tokens manually for GraphQL calls anyway.

  # Also intentionally leaving webhooks empty. Register webhooks in the Shopify Admin dashboard manually.
  # Defining them here triggers another path mutation bug in shopify_app on Rails 8.1.
  config.webhooks = []
end
