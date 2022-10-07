class AddMaxiumBookingHoursPerWeekToSubSpace < ActiveRecord::Migration[6.1]
  def change
    add_column :sub_spaces, :maximum_booking_hours_per_week, :integer
  end
end
