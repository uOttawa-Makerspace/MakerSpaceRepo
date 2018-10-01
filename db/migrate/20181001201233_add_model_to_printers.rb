class AddModelToPrinters < ActiveRecord::Migration
  def change
    add_column :printers, :model, :string
    add_column :printers, :number, :string
  end
end
