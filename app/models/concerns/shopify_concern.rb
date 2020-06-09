module ShopifyConcern
  extend ActiveSupport::Concern

  class_methods do
    def start_shopify_session
      shopify_api_key = Rails.application.secrets.shopify_api_key || ENV.fetch('SHOPIFY_API_KEY')
      shopify_password = Rails.application.secrets.shopify_password || ENV.fetch('SHOPIFY_PASSWORD')
      shopify_shop_name = Rails.application.secrets.shopify_shop_name || ENV.fetch('SHOPIFY_SHOP_NAME')
      shop_url = "https://#{shopify_api_key}:#{shopify_password}@#{shopify_shop_name}.myshopify.com"
      ShopifyAPI::Base.site = shop_url
      ShopifyAPI::Base.api_version = '2020-04'
    end
  end
end