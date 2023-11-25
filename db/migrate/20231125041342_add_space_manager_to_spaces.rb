class AddSpaceManagerToSpaces < ActiveRecord::Migration[7.0]
  def change
    add_reference :spaces, :space_manager
    add_foreign_key :spaces, :users, column: :space_manager_id
  end
end
