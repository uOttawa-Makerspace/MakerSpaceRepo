# frozen_string_literal: true

class RemoveTrainingSessionIdFromUsers < ActiveRecord::Migration[5.0]
  def change
    remove_column :users, :training_session_id, :string
  end
end
