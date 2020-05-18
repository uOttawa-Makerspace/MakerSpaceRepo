class ChangeUserToUsername < ActiveRecord::Migration
  def change
    rename_column :badges, :user, :username
  end
end
