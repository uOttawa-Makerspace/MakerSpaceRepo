class Locker < ApplicationRecord
  has_many :locker_rentals

  validates :specifier, uniqueness: true

  scope :order_by_specifier, -> { order specifier: :asc }

  scope :available,
        -> {
          where
            .missing(:locker_rentals)
            .or(where.not(locker_rentals: { state: :active }))
            .distinct
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
