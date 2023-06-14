class AddTimePeriodToStaffAvailability < ActiveRecord::Migration[7.0]
  def up
    StaffAvailability.destroy_all
    add_reference :staff_availabilities,
                  :time_period,
                  index: true,
                  foreign_key: true
  end

  def down
    remove_reference :staff_availabilities,
                     :time_period,
                     index: true,
                     foreign_key: true
  end
end
