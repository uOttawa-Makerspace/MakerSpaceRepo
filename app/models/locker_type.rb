class LockerType < ApplicationRecord
  has_many :locker_rentals, dependent: :destroy
  enum :available_for,
       { staff: "staff", student: "student", general: "general" }

  validates :short_form,
            :description,
            #:available,
            :available_for,
            :quantity,
            :cost,
            presence: true

  validates :available, inclusion: [true, false]
  validates :short_form, uniqueness: { case_sensitive: false }
  validates :cost, :quantity, comparison: { greater_than_or_equal_to: 0 }

  default_scope { order(:id) }
  scope :available, -> { where(available: true) }

  def active_locker_rentals
    locker_rentals.where(state: :active)
  end

  # Returns number of lockers available for assignment
  def quantity_available
    quantity - locker_rentals.active.count
  end

  def get_available_lockers
    # 1. Make a list based of max quantity (so BRUNS-1, BRUNS-2, ..., BRUNS-99)
    assigned_lockers = locker_rentals.assigned.pluck(:locker_specifier)
    ("1"..quantity.to_s) # 2. Subtract specifiers already assigned to active rentals
      .reject { |specifier| assigned_lockers.include?(specifier) }
  end

  def rgb
    (short_form.sum % 0xFFFFFF).to_s(16)
  end
end
