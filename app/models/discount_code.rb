class DiscountCode < ActiveRecord::Base
  belongs_to :price_rule
  belongs_to :user
  validates :shopify_discount_code_id, presence: true
  validates :code, presence: true

  def self.generate_code
    code = SecureRandom.hex(15)
    while self.code_exist?(code)
      code = SecureRandom.hex(15)
    end
    code
  end

  def self.code_exist?(code)
    DiscountCode.exists?(code: code)
  end

  def self.start_shopify_session
    shopify_session = ShopifyAPI::Session.new(domain: "SHOP_NAME.myshopify.com", api_version: api_version, token: nil)
    ShopifyAPI::Base.activate_session(shopify_session)
  end

  def shopify_api_create_discount_code
    DiscountCode.start_shopify_session
    discount_code = ShopifyAPI::DiscountCode.new
    discount_code.prefix_options[:price_rule_id] = self.price_rule.shopify_price_rule_id
    discount_code.code = self.code
    discount_code.save
    discount_code
  end
end
