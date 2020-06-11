# frozen_string_literal: true

class AddSstPrinterToPrintOrders < ActiveRecord::Migration[5.0]
  def change
    add_column :print_orders, :sst, :boolean
  end
end
