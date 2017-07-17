class RemoveCategoryColumnFromRepositories < ActiveRecord::Migration

  def up
    remove_column :repositories, :category, :string
  end

  def down
  end

end
