class RemoveUserUsernameFromRepositories < ActiveRecord::Migration
  def down
    remove_column :repositories, :user_username, :string
  end
end
