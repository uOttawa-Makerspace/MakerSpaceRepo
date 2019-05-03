class CreateVolunteerHours < ActiveRecord::Migration
  def change
    create_table :volunteer_hours do |t|
      t.integer :volunteer_task_id, null: false
      t.integer :user_id, null: false
      t.datetime :date_of_task
      t.decimal :total_time, precision: 9, scale: 2,  default: 0.00

      t.timestamps null: false
    end
  end
end
