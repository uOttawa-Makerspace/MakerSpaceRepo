class SubSpaceBooking < ApplicationRecord
  belongs_to :user
  belongs_to :sub_space
  has_one :sub_space_booking_status, dependent: :destroy
end
