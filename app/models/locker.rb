class Locker < ApplicationRecord
  has_many :locker_rentals, dependent: :destroy
  belongs_to :locker_size

  validates :specifier, uniqueness: true
  validates :locker_size, presence: true

  scope :order_by_specifier, -> { order specifier: :asc }

  # Because :public is reserved
  scope :public_shown, -> { where(available: true) }
  
  scope :available,
        -> {
          where
            .missing(:locker_rentals)
            .or(where.not(locker_rentals: { state: :active }))
            .distinct
            .includes(:locker_size)
        }
  scope :assigned,
        -> {
          joins(:locker_rentals).where(
            locker_rentals: {
              state: :active
            }
          ).distinct
        }
end
