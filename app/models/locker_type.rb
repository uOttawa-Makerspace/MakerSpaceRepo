class LockerType < ApplicationRecord
  has_many :locker_rentals
  enum available_for: { staff: "staff", student: "student", general: "general" }

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

  def get_available_lockers
    # 1. Make a list based of max quantity (so BRUNS-1, BRUNS-2, ..., BRUNS-99)
    assigned_lockers = locker_rentals.pluck(:locker_specifier)
    ("1"..self.quantity.to_s) # 2. Subtract specifiers already assigned to active rentals
      .reject { |specifier| assigned_lockers.include?(specifier) }
  end

  def generate_line_items
    [
      {
        quantity: 1,
        price_data: {
          currency: "cad",
          product_data: {
            name: "Locker rental",
            description: "#{short_form}"
          },
          unit_amount: (cost * 100.0).to_i
        }
      }
    ]
  end
end
