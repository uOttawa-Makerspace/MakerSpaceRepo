class CreateVolunteerTaskRequest < ActiveRecord::Migration
  def change
    create_table :volunteer_task_requests do |t|
      t.integer :user_id
      t.integer :volunteer_task_id
      t.boolean :approval
    end
  end
end
