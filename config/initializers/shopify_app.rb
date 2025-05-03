# frozen_string_literal: true

ShopifyApp.configure do |config|
  config.secret =
    Rails.application.credentials[Rails.env.to_sym][:shopify][:webhook]
    config.webhooks = [
      #{topic: 'orders/paid', address: 'custom_webooks/orders_paid'},
      # {
      #   topic: 'draft_orders/update',
      #   address: 'custom_webhooks/draft_orders_update',
      #   # Custom namespace for metafields
      #   # metafields are not returned unless asked for, weird
      #   metafield_namespaces: ['makerepo'],
      # }
  ]
end
