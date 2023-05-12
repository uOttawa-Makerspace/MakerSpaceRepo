class CouponCode < ApplicationRecord
  belongs_to :user, optional: true
  include ActionView::Helpers::UrlHelper

  scope :unclaimed, -> { where(user_id: nil) }
  scope :claimed, -> { where.not(user_id: nil) }
  def title
    "$#{dollar_cost} off #{link_to("MakerStore", "https://makerstore.ca/")}".html_safe
  end
end
