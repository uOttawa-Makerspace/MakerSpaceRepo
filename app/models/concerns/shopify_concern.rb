# frozen_string_literal: true

module ShopifyConcern
  extend ActiveSupport::Concern

  class_methods do
    # Authenticated a shopify session and returns it
    def start_shopify_session
      shopify_api_key =
        Rails.application.credentials[Rails.env.to_sym][:shopify][:api_key]
      shopify_password =
        Rails.application.credentials[Rails.env.to_sym][:shopify][:password]
      shopify_shop_name =
        Rails.application.credentials[Rails.env.to_sym][:shopify][:shop_name]
      shopify_api_version = Rails.application.credentials[Rails.env.to_sym][:shopify][:api_version]

      # ShopifyAPI::Base.api_version = shopify_api_version

      session = ShopifyAPI::Auth::Session.new(
        shop: "#{shopify_shop_name}.myshopify.com",
        access_token: shopify_password
      )

      ShopifyAPI::Context.setup(
        api_key: shopify_api_key,
        api_secret_key: shopify_password,
        host: "#{shopify_shop_name}.myshopify.com",
        is_embedded: false, # Not embedded in the Shopify admin UI
        is_private: true,
        api_version: shopify_api_version
      )

      # Activate session to be used in all API calls
      # session must be type `ShopifyAPI::Auth::Session`
      ShopifyAPI::Context.activate_session(session)

      session
      #ShopifyAPI::Context.active_session
    end
  end
end
