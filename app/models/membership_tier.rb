class MembershipTier < ApplicationRecord
  has_many :memberships, dependent: :restrict_with_error

  validates :title_en, :title_fr, presence: true
  validates :internal_price, :external_price, numericality: { greater_than_or_equal_to: 0 }
  validates :duration, numericality: { only_integer: true, greater_than: 0 }

  scope :visible, -> { where(hidden: false) }
  
  def title(locale = I18n.locale)
    locale == :fr ? title_fr : title_en
  end

  def price(user)
    user.internal? ? internal_price : external_price
  end
end
