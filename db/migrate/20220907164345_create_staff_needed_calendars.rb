class CreateStaffNeededCalendars < ActiveRecord::Migration[6.1]
  def change
    create_table :staff_needed_calendars do |t|
      t.string :calendar_url, null: false
      t.string :color
      t.references :space, index: true, foreign_key: true
      t.timestamps
    end
  end
end
