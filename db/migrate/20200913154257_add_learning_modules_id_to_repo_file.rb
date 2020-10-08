class AddLearningModulesIdToRepoFile < ActiveRecord::Migration[6.0]
  def change
    add_column :repo_files, :learning_module_id, :integer
  end
end
