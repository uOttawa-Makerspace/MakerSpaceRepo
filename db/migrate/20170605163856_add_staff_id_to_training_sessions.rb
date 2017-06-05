class AddStaffIdToTrainingSessions < ActiveRecord::Migration
  def change
    add_column :training_sessions, :staff_id, :integer
  end
end
