class CreateVolunteerTaskJoin < ActiveRecord::Migration
  def change
    create_table :volunteer_task_joins do |t|
      t.integer :user_id
      t.integer :volunteer_task_id
      t.string :type, default: "Volunteer"

      t.timestamps null: false
    end
  end
end
