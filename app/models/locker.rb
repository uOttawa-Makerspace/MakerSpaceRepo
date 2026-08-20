class Locker < ApplicationRecord
  has_many :locker_rentals, dependent: :destroy
  belongs_to :locker_size

  # Enum to handle the filter split between staff, design class students (gng), and other (general)
  enum :audience, { general: 'general', staff: 'staff', gng: 'gng' }

  validates :specifier, uniqueness: true
  validates :locker_size, presence: true

  scope :order_by_specifier, -> { order specifier: :asc }

  # Because :public is reserved
  scope :public_shown, -> { where(available: true) }

  # Pass an audience to filter available lockers based on the user requesting.
  # This ensures users can only request lockers designated for their user type.
  scope :available,
        ->(audience = nil) do
          lockers = where.not(
            id: joins(:locker_rentals).where(locker_rentals: { state: :active }).select(:id)
          ).distinct.includes(:locker_size)
          
          # If an audience is provided (e.g. 'staff' or 'gng'), filter the available lockers
          # Using present? prevents empty strings from accidentally filtering out everything
          lockers = lockers.where(audience: audience) if audience.present?
          lockers
        end

  scope :assigned,
        -> do
          joins(:locker_rentals).where(locker_rentals: { state: :active }).distinct
        end
end
