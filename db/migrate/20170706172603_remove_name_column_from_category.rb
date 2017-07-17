class RemoveNameColumnFromCategory < ActiveRecord::Migration

  def up
    remove_column :categories, :name, :string
  end

  def down
  end

end
