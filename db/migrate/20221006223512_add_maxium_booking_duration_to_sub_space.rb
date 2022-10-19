class AddMaxiumBookingDurationToSubSpace < ActiveRecord::Migration[6.1]
  def change
    add_column :sub_spaces, :maximum_booking_duration, :integer
  end
end
