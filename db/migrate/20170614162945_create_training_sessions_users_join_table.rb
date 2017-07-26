class CreateTrainingSessionsUsersJoinTable < ActiveRecord::Migration
  def change
    create_table :training_sessions_users, id: false do |t|
    t.integer :training_session_id
    t.integer :user_id
  end
  add_index :training_sessions_users, :training_session_id
  add_index :training_sessions_users, :user_id
  end
end
