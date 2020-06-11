# frozen_string_literal: true

class CreateJoinTableSpaceTrainings < ActiveRecord::Migration
  def change
    create_join_table :spaces, :trainings do |t|
      # t.index [:space_id, :training_id]
      # t.index [:training_id, :space_id]
    end
  end
end
