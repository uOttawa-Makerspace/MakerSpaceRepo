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
  with_options if: :status_active? do |rental|
    rental.validates :rented_by, :owned_until, presence: true
  end
end
