class AddStudentNumberToUsers < ActiveRecord::Migration[7.0]
  def change
    # Nope they're coming back, sorry arthur
    add_column :users, :student_id, :string
  end
end
