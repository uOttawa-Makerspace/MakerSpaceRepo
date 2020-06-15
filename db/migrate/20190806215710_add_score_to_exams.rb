# frozen_string_literal: true

class AddScoreToExams < ActiveRecord::Migration[5.0]
  def change
    add_column :exams, :score, :integer
  end
end
