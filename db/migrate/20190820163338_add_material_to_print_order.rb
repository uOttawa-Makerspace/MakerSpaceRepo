# frozen_string_literal: true

class AddMaterialToPrintOrder < ActiveRecord::Migration
  def change
    add_column :print_orders, :material, :text
  end
end
