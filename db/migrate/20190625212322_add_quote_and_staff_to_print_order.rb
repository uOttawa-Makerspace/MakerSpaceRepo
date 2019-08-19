class AddQuoteAndStaffToPrintOrder < ActiveRecord::Migration
  def change
    add_column :print_orders, :quote, :float
    add_column :print_orders, :staffid, :float
  end
end
