class AddPinnedBooleanToRepo < ActiveRecord::Migration
  def change
    add_column :repositories, :pinned, :boolean, default: false
  end
end
