class CouponCode < ApplicationRecord
  belongs_to :user, optional: true

  scope :unclaimed, -> { where(user_id: nil) }
  scope :claimed, -> { where.not(user_id: nil) }
  def title
    "#{cc_cost}CCs for $#{dollar_cost}"
  end
end
