# frozen_string_literal: true

class CreateRequireTrainings < ActiveRecord::Migration[5.0]
  def change
    create_table :require_trainings do |t|
      t.integer :volunteer_task_id
      t.integer :training_id

      t.timestamps null: false
    end
  end
end
