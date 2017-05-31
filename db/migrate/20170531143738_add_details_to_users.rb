class AddDetailsToUsers < ActiveRecord::Migration
  def change
  	add_column :users, :student_id, :integer
  	add_column :users, :program, :string
  end
end
