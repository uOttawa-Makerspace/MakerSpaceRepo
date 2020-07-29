class ModifiyMaterialsForPrintOrders < ActiveRecord::Migration[5.2]
  def change
    change_column :print_orders, :grams_fiberglass, :float, default: 0
    change_column :print_orders, :price_per_gram_fiberglass, :float, default: 0
    change_column :print_orders, :grams_carbonfiber, :float, default: 0
    change_column :print_orders, :price_per_gram_carbonfiber, :float, default: 0
  end
end
