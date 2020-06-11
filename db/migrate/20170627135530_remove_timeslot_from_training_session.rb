# frozen_string_literal: true

class RemoveTimeslotFromTrainingSession < ActiveRecord::Migration[5.0]
  def change
    remove_column :training_sessions, :timeslot, :datetime
  end
end
