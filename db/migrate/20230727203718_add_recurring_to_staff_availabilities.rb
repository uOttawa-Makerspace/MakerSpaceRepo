class AddRecurringToStaffAvailabilities < ActiveRecord::Migration[7.0]
  def change
    add_column :staff_availabilities, :recurring, :boolean, default: true
    add_column :staff_availabilities, :start_datetime, :datetime
    add_column :staff_availabilities, :end_datetime, :datetime
  end
end
