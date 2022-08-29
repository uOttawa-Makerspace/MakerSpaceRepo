class AddDeletedToRepositories < ActiveRecord::Migration[6.1]
  def self.up
    add_column :repositories, :deleted, :boolean
    Repository.update_all(deleted: false)
  end
  def self.down
    remove_column :repositories, :deleted
  end
end
