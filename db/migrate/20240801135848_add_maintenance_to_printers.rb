class AddMaintenanceToPrinters < ActiveRecord::Migration[7.0]
  def change
    add_column :printers, :maintenance, :boolean, default: false
  end
end
