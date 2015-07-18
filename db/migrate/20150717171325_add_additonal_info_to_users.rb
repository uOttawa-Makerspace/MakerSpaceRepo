class AddAdditonalInfoToUsers < ActiveRecord::Migration
  def change
    add_column :users, :gender, :string
    add_column :users, :faculty, :string
    add_column :users, :use, :string
  end
end
