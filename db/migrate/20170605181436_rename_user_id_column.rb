class RenameUserIdColumn < ActiveRecord::Migration
  def change
  	rename_column :users, :studentID, :student_id
  end
end
