class SubSpaceBookingStatus < ApplicationRecord
  belongs_to :sub_space_booking
  belongs_to :booking_status
end
