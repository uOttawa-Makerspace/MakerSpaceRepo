class AddLockedLockedUntilAuthAttemptsToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :locked, :boolean, default: false
    add_column :users, :locked_until, :datetime
    add_column :users, :auth_attempts, :integer, default: 0
  end
end
