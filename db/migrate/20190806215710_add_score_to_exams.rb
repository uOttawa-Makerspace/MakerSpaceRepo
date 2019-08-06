class AddScoreToExams < ActiveRecord::Migration
  def change
    add_column :exams, :score, :integer
  end
end