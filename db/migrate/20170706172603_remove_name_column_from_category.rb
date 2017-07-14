class RemoveNameColumnFromCategory < ActiveRecord::Migration
  def down
    remove_column :categories, :name, :string
    
  end
end
