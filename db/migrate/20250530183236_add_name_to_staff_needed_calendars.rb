class AddNameToStaffNeededCalendars < ActiveRecord::Migration[7.2]
  def change
    add_column :staff_needed_calendars, :name, :string
  end
end
