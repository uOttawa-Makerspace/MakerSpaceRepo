# frozen_string_literal: true

# Primes ShopifyAPI::Context once per process (Puma worker/master, solid_queue, console).
#
# ShopifyConcern.start_shopify_session only activates a session; since 3358306d0 it no
# longer calls Context.setup (production's master still does, on every call). Without
# this, a process whose first Shopify call is a draft order (membership, locker, job
# order) would POST to /admin/api//graphql.json (empty API version).
#
# Arguments are exactly those master's ShopifyConcern#start_shopify_session passed.
# Context.setup only reassigns settings (and reloads the version's REST resources), so
# ShopifyService.start_shopify_session calling it again later is harmless.
shopify_config = Rails.application.credentials.dig(Rails.env.to_sym, :shopify)

if shopify_config.present? && shopify_config[:api_version].present? && shopify_config[:shop_name].present?
  begin
    ShopifyAPI::Context.setup(
      api_key: shopify_config[:api_key],
      api_secret_key: shopify_config[:password],
      host: "#{shopify_config[:shop_name]}.myshopify.com",
      is_embedded: false, # Not embedded in the Shopify admin UI
      is_private: true,
      api_version: shopify_config[:api_version]
    )
  rescue StandardError => e
    # Never take the site down at boot over Shopify config (e.g. an unsupported api_version).
    Rails.logger.warn("[shopify_api] ShopifyAPI::Context.setup skipped: #{e.class}: #{e.message}")
  end
else
  Rails.logger.warn(
    "[shopify_api] credentials.#{Rails.env}.shopify (shop_name, api_version) is missing: " \
    "ShopifyAPI::Context.setup skipped; Shopify calls will fail until it is configured."
  )
end
