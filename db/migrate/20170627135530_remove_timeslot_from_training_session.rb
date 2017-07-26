class RemoveTimeslotFromTrainingSession < ActiveRecord::Migration
  def change
    remove_column :training_sessions, :timeslot, :datetime
  end
end
