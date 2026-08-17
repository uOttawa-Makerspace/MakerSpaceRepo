# frozen_string_literal: true

ShopifyApp.configure do |config|
  # Safely fetch the secret without throwing undefined method '[]' for nil in test/CI
  config.secret = Rails.application.credentials.dig(Rails.env.to_sym, :shopify, :webhook) || "test_secret"

  # NOTE: We intentionally do NOT set config.api_key here. 
  # If api_key is present, shopify_app treats this as a public OAuth app and tries to 
  # mutate autoload paths, which crashes on Rails 8.1+ with a FrozenError.
  # Leaving it blank keeps it in "private app" mode. Our ShopifyConcern handles the 
  # actual API key and access tokens manually for GraphQL calls anyway.

  # Also intentionally leaving webhooks empty. Register webhooks in the Shopify Admin dashboard manually.
  # Defining them here triggers another path mutation bug in shopify_app on Rails 8.1.
  config.webhooks = []
end
