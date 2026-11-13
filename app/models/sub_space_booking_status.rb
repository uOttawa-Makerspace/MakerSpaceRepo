class SubSpaceBookingStatus < ApplicationRecord
  belongs_to :sub_space_booking
  belongs_to :booking_status

  # A row a booking still points at cannot be destroyed, and destroying a row never removes its booking.
  # SubSpaceBooking#destroy_with_status! clears that link first.
  has_many :sub_space_bookings, foreign_key: :sub_space_booking_status_id,
                                inverse_of: :sub_space_booking_status,
                                dependent: :restrict_with_error
end
