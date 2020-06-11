# frozen_string_literal: true

class CreateVolunteerTasks < ActiveRecord::Migration[5.0]
  def change
    create_table :volunteer_tasks do |t|
      t.string :title, default: ''
      t.text :description, default: ''
      t.integer :user_id
      t.boolean :active, default: true

      t.timestamps null: false
    end
  end
end
