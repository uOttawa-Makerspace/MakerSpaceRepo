class RemoveProjectKitFromLearningModule < ActiveRecord::Migration[6.0]
  def change
    remove_column :learning_modules, :has_project_kit
  end
end
