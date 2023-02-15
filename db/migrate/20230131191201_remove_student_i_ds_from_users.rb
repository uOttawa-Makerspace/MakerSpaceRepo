class RemoveStudentIDsFromUsers < ActiveRecord::Migration[6.1]
  def change
    remove_column :users, :student_id, :integer
  end
end
