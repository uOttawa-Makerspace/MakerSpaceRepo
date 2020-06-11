# frozen_string_literal: true

class AddCourseToTrainingSession < ActiveRecord::Migration
  def change
    add_column :training_sessions, :course, :string
  end
end
