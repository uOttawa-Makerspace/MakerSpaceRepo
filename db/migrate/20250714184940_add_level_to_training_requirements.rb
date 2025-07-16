class AddLevelToTrainingRequirements < ActiveRecord::Migration[7.2]
  def change
    add_column :training_requirements, :level, :string
  end
end
