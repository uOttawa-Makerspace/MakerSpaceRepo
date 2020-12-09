class CreateJoinTableUsersLearningModules < ActiveRecord::Migration[6.0]
  def change
    create_join_table :users, :learning_module do |t|
      # t.index [:user_id, :proficient_project_id]
      # t.index [:proficient_project_id, :user_id]
    end
  end
end
