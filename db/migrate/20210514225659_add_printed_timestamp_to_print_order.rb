class AddPrintedTimestampToPrintOrder < ActiveRecord::Migration[6.0]
  def change
    add_column :print_orders, :timestamp_printed, :timestamp
  end
end
