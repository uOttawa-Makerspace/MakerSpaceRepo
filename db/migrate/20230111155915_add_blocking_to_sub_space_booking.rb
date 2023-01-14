class AddBlockingToSubSpaceBooking < ActiveRecord::Migration[6.1]
  def change
    add_column :sub_space_bookings, :blocking, :boolean, default: false
  end
end
