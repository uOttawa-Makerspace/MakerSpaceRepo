class AddDeletedToRepositories < ActiveRecord::Migration[6.1]
  def change
    add_column :repositories, :deleted, :boolean, default: false
  end
end
