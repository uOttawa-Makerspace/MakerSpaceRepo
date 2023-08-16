class KeyTransaction < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :key, optional: true

  validates :user, presence: true
  validates :key, presence: true
  validates :deposit_amount, presence: true

  scope :returned, -> { where.not(return_date: nil) }
  scope :not_returned, -> { where(return_date: nil) }
  scope :deposit_unpaid,
        -> { where.not(return_date: nil).and(where(deposit_return_date: nil)) }
end
