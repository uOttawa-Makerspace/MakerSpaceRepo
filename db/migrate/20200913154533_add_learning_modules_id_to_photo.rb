class AddLearningModulesIdToPhoto < ActiveRecord::Migration[6.0]
  def change
    add_column :photos, :learning_module_id, :integer
  end
end
