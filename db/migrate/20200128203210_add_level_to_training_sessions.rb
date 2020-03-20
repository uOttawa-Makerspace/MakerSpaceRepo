class AddLevelToTrainingSessions < ActiveRecord::Migration
  def change
    add_column :training_sessions, :level, :string, default: "Beginner"
  end
end
