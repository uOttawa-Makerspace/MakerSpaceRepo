class DropTrainingLevelsAndSpaceStaffHours < ActiveRecord::Migration[7.0]
  def up
    drop_table :space_staff_hours
    drop_table :training_levels
  end

  def down
    create_table :training_levels do |t|
      t.string :name
      t.references :space
      t.timestamps
    end

    create_table :space_staff_hours do |t|
      t.references :space
      t.integer :day
      t.time :start_time
      t.time :end_time
      t.string :language
      t.references :course_name
      t.references :training_level
      t.timestamps
    end
  end
end