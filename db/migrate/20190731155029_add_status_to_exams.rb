class AddStatusToExams < ActiveRecord::Migration
  def change
    add_column :exams, :status, :string, default: "not started"
  end
end
