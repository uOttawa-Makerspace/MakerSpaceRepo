class ChangeTypeToOrderType < ActiveRecord::Migration
  def change
    rename_column :print_orders, :type, :order_type
  end
end
