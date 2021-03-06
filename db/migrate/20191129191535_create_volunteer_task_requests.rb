# frozen_string_literal: true

class CreateVolunteerTaskRequests < ActiveRecord::Migration[5.0]
  def change
    create_table :volunteer_task_requests do |t|
      t.integer :user_id
      t.integer :volunteer_task_id
      t.boolean :approval

      t.timestamps null: false
    end
  end
end
