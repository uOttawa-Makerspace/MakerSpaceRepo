class AddGoogleBookingIdToSubSpaceBooking < ActiveRecord::Migration[7.2]
  def up
    add_column :sub_space_bookings, :google_booking_id, :string
  end

  def down
    remove_column :sub_space_bookings, :google_booking_id, :string
  end
end
