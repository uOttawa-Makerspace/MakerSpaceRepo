class DiscountCode < ActiveRecord::Base
  include ShopifyConcern
  belongs_to :price_rule
  belongs_to :user
  has_many :cc_moneys, dependent: :destroy
  validates :shopify_discount_code_id, presence: true
  validates :code, presence: true
  scope :used_code, -> {where(usage_count: 1)}
  scope :not_used, -> {where(usage_count: 0)}

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

  def self.start_session
    start_shopify_session
  end

  def status
    self.usage_count == 0 ? "Not used" : "Used"
  end

  def shopify_api_create_discount_code
    DiscountCode.start_session
    shopify_discount_code = ShopifyAPI::DiscountCode.new
    shopify_discount_code.prefix_options[:price_rule_id] = self.price_rule.shopify_price_rule_id
    shopify_discount_code.code = self.code
    shopify_discount_code.save
    shopify_discount_code
  end

  def delete_discount_code_from_shopify
    DiscountCode.start_session
    shopify_discount_code = ShopifyAPI::DiscountCode.find(self.shopify_discount_code_id)
    shopify_discount_code.destroy
  end
end
