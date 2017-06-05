class AddTrainingSessionIdToUser < ActiveRecord::Migration
  def change
    add_column :users, :training_session_id, :string
  end
end
