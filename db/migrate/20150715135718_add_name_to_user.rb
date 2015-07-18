class AddNameToUser < ActiveRecord::Migration
  def change
    add_column :users, :name, :string
    remove_column :users, :first_name, :string
    remove_column :users, :last_name, :string
  end
end
