class AddDeletedToUsers < ActiveRecord::Migration[6.1]
  def self.up
    add_column :users, :deleted, :boolean
    User.unscoped.update_all(deleted: false)
  end
  def self.down
    remove_column :users, :deleted
  end
end
