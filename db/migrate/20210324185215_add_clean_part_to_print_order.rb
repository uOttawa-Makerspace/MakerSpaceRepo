class AddCleanPartToPrintOrder < ActiveRecord::Migration[6.0]
  def change
    add_column :print_orders, :clean_part, :boolean
  end
end
