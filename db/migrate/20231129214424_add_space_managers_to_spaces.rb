class AddSpaceManagersToSpaces < ActiveRecord::Migration[7.0]
  def change
    create_table :space_manager_joins do |t|
      t.references :user
      t.references :space

      t.timestamps
    end
  end
end
