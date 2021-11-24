class CreateSpaceStaffHours < ActiveRecord::Migration[6.0]
  def change
    create_table :space_staff_hours do |t|
      t.time :start_time
      t.time :end_time
      t.integer :day
      t.references :space, foreign_key: true
      t.timestamps
    end
  end
end
