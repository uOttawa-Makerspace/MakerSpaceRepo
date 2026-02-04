class SubSpaceBookingStatus < ApplicationRecord
  belongs_to :sub_space_booking,
             dependent: :destroy
  has_one :booking_status
end
