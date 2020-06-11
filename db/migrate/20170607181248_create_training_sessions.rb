# frozen_string_literal: true

class CreateTrainingSessions < ActiveRecord::Migration
  def change
    create_table :training_sessions do |t|
      t.references :training, index: true, foreign_key: true
      t.references :user, index: true, foreign_key: true
      t.datetime :timeslot

      t.timestamps null: false
    end
  end
end
