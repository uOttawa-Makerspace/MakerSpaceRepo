ShopifyApp.configure do |config|
  config.secret = ENV.fetch('SHOPIFY_WEBHOOK')
  config.webhooks = [
      {topic: 'orders/paid', address: 'http://localhost:3000/custom_webooks/orders_paid', fields: ['discount_codes']}
  ]
end