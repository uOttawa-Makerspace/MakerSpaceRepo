class EditTrainingSessions < ActiveRecord::Migration
  def change
    remove_column :training_sessions, :date
    remove_column :training_sessions, :time
    add_column :training_sessions, :session_time, :datetime 
  end
end
