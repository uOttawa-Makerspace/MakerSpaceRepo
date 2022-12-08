class AddPublicToSubSpaceBookings < ActiveRecord::Migration[6.1]
  def change
    add_column :sub_space_bookings, :public, :boolean, default: false
  end
  def up
    SubSpaceBooking.update_all(public: false)
  end
end
