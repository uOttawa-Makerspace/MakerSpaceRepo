class SubSpaceBookingStatus < ApplicationRecord
  belongs_to :sub_space_booking,
             dependent: :destroy
  belongs_to :booking_status
end
