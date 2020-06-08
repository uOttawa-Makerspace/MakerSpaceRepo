class PriceRule < ActiveRecord::Base
  has_many :discount_codes, dependent: :destroy
end
