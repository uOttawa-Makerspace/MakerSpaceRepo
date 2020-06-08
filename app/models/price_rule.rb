class PriceRule < ActiveRecord::Base
  has_many :discount_codes, dependent: :destroy
  validates :shopify_price_rule_id, presence: true
  validates :title, presence: true
end
