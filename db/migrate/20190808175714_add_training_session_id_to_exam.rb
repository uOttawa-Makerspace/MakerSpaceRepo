# frozen_string_literal: true

class AddTrainingSessionIdToExam < ActiveRecord::Migration[5.0]
  def change
    add_column :exams, :training_session_id, :integer
  end
end
