class AddCourseNameToTrainingSession < ActiveRecord::Migration[6.0]
  def change
    add_column :training_sessions, :course_name_id, :integer
  end
end
