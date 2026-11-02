# frozen_string_literal: true

require Rails.root.join("lib/shopify_webhook_secret")

ShopifyApp.configure do |config|
  # No fallback outside test/development: a missing credential leaves the secret nil,
  # the app boots, and the orders_paid webhook answers 503 (and reports) until it is set.
  webhook_secret = ShopifyWebhookSecret.resolve(
    env: Rails.env,
    credential: Rails.application.credentials.dig(Rails.env.to_sym, :shopify, :webhook)
  )
  config.secret = webhook_secret

  unless ShopifyWebhookSecret.configured?(webhook_secret)
    Rails.logger.warn(
      "[shopify_app] Shopify webhook secret is missing (credentials.#{Rails.env}.shopify.webhook): " \
      "the app boots, but every /custom_webhooks/orders_paid request will be refused with 503 until it is set."
    )
  end

  # NOTE: We intentionally do NOT set config.api_key here. 
  # If api_key is present, shopify_app treats this as a public OAuth app and tries to 
  # mutate autoload paths, which crashes on Rails 8.1+ with a FrozenError.
  # Leaving it blank keeps it in "private app" mode. Our ShopifyConcern handles the 
  # actual API key and access tokens manually for GraphQL calls anyway.

  # Also intentionally leaving webhooks empty. Register webhooks in the Shopify Admin dashboard manually.
  # Defining them here triggers another path mutation bug in shopify_app on Rails 8.1.
  config.webhooks = []
end
