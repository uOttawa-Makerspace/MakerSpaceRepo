class AddTrainingLevelToTrainings < ActiveRecord::Migration[7.2]
  def change
    add_column :trainings, :training_level, :string
  end
end
