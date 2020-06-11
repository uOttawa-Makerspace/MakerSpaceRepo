# frozen_string_literal: true

class AddHoursInPrintOrders < ActiveRecord::Migration[5.0]
  def change
    add_column :print_orders, :hours, :float
  end
end
