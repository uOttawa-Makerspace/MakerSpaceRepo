class AddRecurringToStaffAvailabilities < ActiveRecord::Migration[7.0]
  def change
    add_column :staff_availabilities, :recurring, :boolean, default: true
  end
end
