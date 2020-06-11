# frozen_string_literal: true

class AddCourseToTrainingSession < ActiveRecord::Migration[5.0]
  def change
    add_column :training_sessions, :course, :string
  end
end
