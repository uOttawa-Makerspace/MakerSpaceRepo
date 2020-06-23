# frozen_string_literal: true

ShopifyApp.configure do |config|
  config.secret = Rails.application.credentials[Rails.env.to_sym][:shopify][:webhook]
end
