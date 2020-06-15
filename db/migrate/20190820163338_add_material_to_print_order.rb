# frozen_string_literal: true

class AddMaterialToPrintOrder < ActiveRecord::Migration[5.0]
  def change
    add_column :print_orders, :material, :text
  end
end
