class LockerType < ApplicationRecord
  has_many :locker_rentals
  enum available_for: { staff: "staff", student: "student", general: "general" }

  validates :short_form,
            :description,
            :available,
            :available_for,
            :quantity,
            :cost,
            presence: true

  validates :short_form, uniqueness: { case_sensitive: false }
  validates :cost, :quantity, comparison: { greater_than_or_equal_to: 0 }
end
