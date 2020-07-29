class RemoveNotUsedColumnsForPrintOrdersAndAddCommentsForStaff < ActiveRecord::Migration[5.2]
  def change
    add_column :print_orders, :comments_for_staff, :string
    remove_column :print_orders, :grams2
    remove_column :print_orders, :price_per_gram2
  end
end
