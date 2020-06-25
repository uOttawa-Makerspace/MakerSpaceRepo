# frozen_string_literal: true

module ShopifyConcern
  extend ActiveSupport::Concern

  class_methods do
    def start_shopify_session
      shopify_api_key = Rails.application.credentials[Rails.env.to_sym][:shopify][:api_key]
      shopify_password = Rails.application.credentials[Rails.env.to_sym][:shopify][:password]
      shopify_shop_name = Rails.application.credentials[Rails.env.to_sym][:shopify][:shop_name]
      shop_url = "https://#{shopify_api_key}:#{shopify_password}@#{shopify_shop_name}.myshopify.com"
      ShopifyAPI::Base.site = shop_url
      ShopifyAPI::Base.api_version = Rails.application.credentials[Rails.env.to_sym][:shopify][:api_version]
    end
  end
end
