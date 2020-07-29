class AddMaterialColumnsForPrintOrder < ActiveRecord::Migration[5.2]
  def change
    add_column :print_orders, :grams_fiberglass, :float
    add_column :print_orders, :price_per_gram_fiberglass, :float
    add_column :print_orders, :grams_carbonfiber, :float
    add_column :print_orders, :price_per_gram_carbonfiber, :float
  end
end
