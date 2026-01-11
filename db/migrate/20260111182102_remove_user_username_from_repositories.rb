class RemoveUserUsernameFromRepositories < ActiveRecord::Migration[7.2]
  def change
    remove_column :repositories, :user_username, :string
  end
end
