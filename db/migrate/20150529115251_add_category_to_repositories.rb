class AddCategoryToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :category, :string
  end
end
