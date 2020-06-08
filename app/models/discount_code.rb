class DiscountCode < ActiveRecord::Base
  belongs_to :price_rule
  belongs_to :user
end
