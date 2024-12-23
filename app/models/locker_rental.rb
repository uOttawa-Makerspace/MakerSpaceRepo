# frozen_string_literal: true

class LockerRental < ApplicationRecord
  belongs_to :locker_type
  belongs_to :rented_by, class_name: "User"

  enum state: {
         # Users submitted, not approved by admin
         reviewing: "reviewing",
         # Approved by admin, waiting for payment confirm
         await_payment: "await_payment",
         # Approved and paid, or assigned directly by admin
         active: "active",
         # Cancelled, no longer assigned
         cancelled: "cancelled"
       }

  validates :locker_type, :state, presence: true

  with_options if: :active? do |rental|
    # Don't double assign lockers of same locker type if full assigned
    # TODO upgrade Rails and add normalization to trim spaces
    # or change column type to integer not string
    validates :locker_specifier,
              uniqueness: {
                scope: :locker_type
              },
              allow_nil: true
    rental.validates :rented_by, :owned_until, :locker_specifier, presence: true
  end

  def full_locker_name
    "#{locker_type.short_form}##{locker_specifier}"
  end

  def state_icon
    LockerRental.state_icon(state)
  end

  def self.state_icon(state)
    case state
    when "active"
      "fa-lock"
    when "cancelled"
      "fa-clock-o text-danger"
    else
      ""
    end
  end

  def self.get_assigned_lockers
    LockerRental
      .where(state: :active)
      .pluck(:locker_type_id, :locker_specifier)
      .group_by(&:shift)
      .transform_values(&:flatten)
  end

  def self.get_available_lockers
    assigned_lockers = get_assigned_lockers
    LockerType.all.map do |type|
      [
        type.short_form,
        # 1. Make a list based of max quantity (so BRUNS-1, BRUNS-2, ..., BRUNS-99)
        ("1"..type.quantity.to_s) # 2. Subtract specifiers already assigned to active rentals
          .reject do |specifier|
          assigned_lockers[type.id] &&
            assigned_lockers[type.id].include?(specifier)
        end
      ]
    end
  end
end
