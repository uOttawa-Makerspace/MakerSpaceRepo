class AddLikesToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :likes, :integer, default: 0
  end
end
