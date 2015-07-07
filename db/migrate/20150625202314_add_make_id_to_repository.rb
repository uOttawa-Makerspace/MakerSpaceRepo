class AddMakeIdToRepository < ActiveRecord::Migration
  def change
    add_column :repositories, :make_id, :integer
  end
end
