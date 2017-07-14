class RemoveCategoryColumnFromRepositories < ActiveRecord::Migration
  def down
    remove_column :repositories, :category, :string
  end
end
