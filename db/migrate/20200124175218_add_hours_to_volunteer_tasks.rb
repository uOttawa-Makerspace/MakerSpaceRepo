class AddHoursToVolunteerTasks < ActiveRecord::Migration
  def change
    add_column :volunteer_tasks, :hours, :decimal, precision: 5, scale: 2, default: 0.00
  end
end
