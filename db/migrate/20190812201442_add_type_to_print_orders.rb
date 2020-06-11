# frozen_string_literal: true

class AddTypeToPrintOrders < ActiveRecord::Migration[5.0]
  def change
    add_column :print_orders, :type, :integer, default: 0
  end
end
