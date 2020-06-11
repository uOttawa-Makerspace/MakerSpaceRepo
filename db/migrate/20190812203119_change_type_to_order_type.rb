# frozen_string_literal: true

class ChangeTypeToOrderType < ActiveRecord::Migration[5.0]
  def change
    rename_column :print_orders, :type, :order_type
  end
end
