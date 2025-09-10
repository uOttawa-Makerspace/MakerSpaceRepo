class AddRoleToStaffNeededCalendars < ActiveRecord::Migration[7.2]
  def change
    add_column :staff_needed_calendars, :role, :string

    add_index :staff_needed_calendars,
              [:space_id],
              unique: true,
              where: "role = 'open_hours'",
              name: "index_unique_open_hours_per_space"
  end
end