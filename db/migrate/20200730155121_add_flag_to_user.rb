class AddFlagToUser < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :flagged, :boolean
    add_column :users, :flag_message, :string
  end
end
