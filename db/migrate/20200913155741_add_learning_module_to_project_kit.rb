class AddLearningModuleToProjectKit < ActiveRecord::Migration[6.0]
  def change
    add_reference :project_kits, :learning_module, index: true, foreign_key: true
  end
end
