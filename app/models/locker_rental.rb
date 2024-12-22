# frozen_string_literal: true

class LockerRental < ApplicationRecord
  belongs_to :locker_type
  belongs_to :rented_by, class_name: "User"

  enum state: {
         reviewing: "reviewing",
         await_payment: "await_payment",
         active: "active",
         cancelled: "cancelled"
       }

  validates :locker_type, :state, presence: true
  with_options if: :active? do |rental|
    rental.validates :rented_by, :owned_until, presence: true
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
      .all
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
