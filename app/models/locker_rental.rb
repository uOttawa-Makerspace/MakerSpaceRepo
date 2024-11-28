class LockerRental < ApplicationRecord
  belongs_to :locker_type
  belongs_to :rented_by, class_name: "User"
end
