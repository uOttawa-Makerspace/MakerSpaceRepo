class AddPaidAndPickedUpToPrintOrder < ActiveRecord::Migration[6.0]
  def change
    add_column :print_orders, :payed, :boolean
    add_column :print_orders, :picked_up, :boolean
  end
end
