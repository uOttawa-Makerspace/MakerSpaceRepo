# frozen_string_literal: true

class AddQuoteAndStaffToPrintOrder < ActiveRecord::Migration[5.0]
  def change
    add_column :print_orders, :quote, :float
    add_column :print_orders, :staffid, :float
  end
end
