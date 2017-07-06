class RemoveNameColumnFromCategory < ActiveRecord::Migration
  def change
    remove_column :categories, :name, :string
  end
end
