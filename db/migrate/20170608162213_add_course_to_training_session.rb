class AddCourseToTrainingSession < ActiveRecord::Migration
  def change
    add_column :training_sessions, :course, :string
  end
end
