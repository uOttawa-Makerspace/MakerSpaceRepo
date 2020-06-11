# frozen_string_literal: true

class RenameUserIdColumn < ActiveRecord::Migration[5.0]
  def change
    rename_column :users, :studentID, :student_id
  end
end
