class Locker < ApplicationRecord
  has_many :locker_rentals, dependent: :destroy
  belongs_to :locker_size

  validates :specifier, uniqueness: true
  validates :locker_size, presence: true

  scope :order_by_specifier, -> { order specifier: :asc }

  # Because :public is reserved
  scope :public_shown, -> { where(available: true) }

  # Get all lockers, then subtract those with a subquery for lockers with an
  # active rental.
  scope :available,
        -> do
          where
            .not(
              id:
                joins(:locker_rentals).where(
                  locker_rentals: {
                    state: :active
                  }
                ).select(:id)
            )
            .distinct
            .includes(:locker_size)
        end
  scope :assigned,
        -> do
          joins(:locker_rentals).where(
            locker_rentals: {
              state: :active
            }
          ).distinct
        end
end
