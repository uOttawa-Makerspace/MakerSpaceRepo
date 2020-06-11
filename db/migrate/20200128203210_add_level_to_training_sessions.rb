# frozen_string_literal: true

class AddLevelToTrainingSessions < ActiveRecord::Migration[5.0]
  def change
    add_column :training_sessions, :level, :string, default: 'Beginner'
  end
end
