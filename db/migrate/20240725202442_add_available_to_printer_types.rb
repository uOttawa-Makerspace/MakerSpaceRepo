class AddAvailableToPrinterTypes < ActiveRecord::Migration[7.0]
  def change
    add_column :printer_types, :available, :boolean, default: true
  end
end
