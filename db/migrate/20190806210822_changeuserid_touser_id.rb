class ChangeuseridTouserId < ActiveRecord::Migration
  def change
    rename_column :print_orders, :userid, :user_id
  end
end
