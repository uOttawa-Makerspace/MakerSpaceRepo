class AddDescriptionToUsers < ActiveRecord::Migration
  def change
    add_column :users, :description, :text
    add_column :users, :email, :string
  end
end
