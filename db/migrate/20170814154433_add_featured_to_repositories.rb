class AddFeaturedToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :featured, :boolean, default: false
  end
end
