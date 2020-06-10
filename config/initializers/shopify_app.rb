ShopifyApp.configure do |config|
  config.secret = Rails.application.secrets.shopify_webhook || ENV.fetch('SHOPIFY_WEBHOOK', 'travis')
end