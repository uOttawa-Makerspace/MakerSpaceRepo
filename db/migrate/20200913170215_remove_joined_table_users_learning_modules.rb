class RemoveJoinedTableUsersLearningModules < ActiveRecord::Migration[6.0]
  def change
    drop_join_table :learning_module, :users
  end
end
