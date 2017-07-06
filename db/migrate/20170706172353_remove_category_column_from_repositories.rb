class RemoveCategoryColumnFromRepositories < ActiveRecord::Migration
  def change
    remove_column :repositories, :category, :string
  end
end
