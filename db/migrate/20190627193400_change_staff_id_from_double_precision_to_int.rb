class ChangeStaffIdFromDoublePrecisionToInt < ActiveRecord::Migration
  def change
    change_column :print_orders, :staffid, :integer
  end
end
