class AddTypeToPrintOrders < ActiveRecord::Migration
  def change
    add_column :print_orders, :type, :integer, default: 0
  end
end
