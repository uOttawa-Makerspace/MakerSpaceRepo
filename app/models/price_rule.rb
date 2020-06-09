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

end