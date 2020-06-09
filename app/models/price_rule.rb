class PriceRule < ActiveRecord::Base
  include ShopifyConcern
  has_many :discount_codes, dependent: :destroy
  validates :shopify_price_rule_id, presence: true
  validates :title, presence: true
  validates :value, presence: true
  validates :cc, presence: true

  def self.create_price_rule(title, value)
    start_shopify_session
    price_rule = ShopifyAPI::PriceRule.create(
        title: title,
        target_type: "line_item",
        target_selection: "all",
        allocation_method: "across",
        value_type: "fixed_amount",
        value: "-" + value.to_s,
        customer_selection: "all",
        starts_at: Time.now.iso8601,
        usage_limit: 1
    )
    return price_rule.id
  end

  def self.delete_price_rule_from_shopify(shopify_price_rule_id)
    start_shopify_session
    shopify_price_rule = ShopifyAPI::PriceRule.find(shopify_price_rule_id)
    shopify_price_rule.destroy
  end

  def self.update_price_rule(id, title, value)
    start_shopify_session
    price_rule = ShopifyAPI::PriceRule.find(id)
    price_rule.title = title
    price_rule.value = "-" + value.to_s
    price_rule.save
  end

  def has_discount_codes?
    self.discount_codes.present?
  end

end