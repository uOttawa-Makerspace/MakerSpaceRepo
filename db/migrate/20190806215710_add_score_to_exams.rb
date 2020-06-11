# frozen_string_literal: true

class AddScoreToExams < ActiveRecord::Migration
  def change
    add_column :exams, :score, :integer
  end
end
