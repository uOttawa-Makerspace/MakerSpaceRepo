# frozen_string_literal: true

class AddSpaceIdToTrainingSession < ActiveRecord::Migration
  def change
    add_column :training_sessions, :space_id, :integer
  end
end
