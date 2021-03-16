class AddDestroyAdminIdToSpace < ActiveRecord::Migration[6.0]
  def change
    add_column :spaces, :destroy_admin_id, :integer
  end
end
