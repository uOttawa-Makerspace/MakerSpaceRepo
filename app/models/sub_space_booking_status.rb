class SubSpaceBookingStatus < ApplicationRecord
  belongs_to :sub_space_booking,
             foreign_key: :sub_space_booking_id,
             dependent: :destroy
  has_one :booking_status
end
