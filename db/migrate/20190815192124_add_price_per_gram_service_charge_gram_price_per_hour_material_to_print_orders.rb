# frozen_string_literal: true

class AddPricePerGramServiceChargeGramPricePerHourMaterialToPrintOrders < ActiveRecord::Migration
  def change
    add_column :print_orders, :grams, :float
    add_column :print_orders, :service_charge, :float
    add_column :print_orders, :price_per_hour, :float
    add_column :print_orders, :price_per_gram, :float
    add_column :print_orders, :material_cost, :float
  end
end
