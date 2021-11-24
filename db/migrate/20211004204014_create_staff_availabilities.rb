class CreateStaffAvailabilities < ActiveRecord::Migration[6.0]
  def change
    create_table :staff_availabilities do |t|
      t.references :user, foreign_key: true
      t.string :day
      t.time :start_time
      t.time :end_time
      t.timestamps
    end
  end
end
