class AddTrainingSessionIdToExam < ActiveRecord::Migration
  def change
    add_column :exams, :training_session_id, :integer
  end
end
