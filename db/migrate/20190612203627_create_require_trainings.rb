class CreateRequireTrainings < ActiveRecord::Migration
  def change
    create_table :require_trainings do |t|
      t.integer :volunteer_task_id
      t.integer :training_id

      t.timestamps null: false
    end
  end
end
