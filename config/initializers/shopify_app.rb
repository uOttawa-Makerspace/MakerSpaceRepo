ShopifyApp.configure do |config|
  config.secret = Rails.application.secrets.shopify_webhook || ENV.fetch('SHOPIFY_WEBHOOK', 'travis')
  config.webhooks = [
      {topic: 'orders/paid', address: 'http://localhost:3000/custom_webooks/orders_paid', fields: ['discount_codes']}
  ]
end