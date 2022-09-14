class AddSubSpaceBookingStatusToSubSpaceBookings < ActiveRecord::Migration[6.1]
  def change
    add_reference :sub_space_bookings,
                  :sub_space_booking_status,
                  foreign_key: true
    add_reference :sub_space_booking_statuses,
                  :booking_status,
                  foreign_key: true
  end
end
