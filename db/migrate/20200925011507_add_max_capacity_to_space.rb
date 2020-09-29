class AddMaxCapacityToSpace < ActiveRecord::Migration[6.0]
  def change
    add_column :spaces, :max_capacity, :integer
  end
end
