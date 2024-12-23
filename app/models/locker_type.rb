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

  scope :available, -> { where(available: true) }

  def active_locker_rentals
    locker_rentals.where(state: :active)
  end
end
