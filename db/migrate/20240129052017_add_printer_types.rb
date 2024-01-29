class AddPrinterTypes < ActiveRecord::Migration[7.0]
  def change
    # Create the PrinterType table
    create_table :printer_types do |t|
      t.string :name

      t.timestamps
    end

    # add printer_type_id to printers table
    add_reference :printers, :printer_type, index: true, foreign_key: true

    # populate printer types
    Printer.all.each do |printer|
      printer_model = printer.model

      if PrinterType.where(name: printer_model).empty?
        PrinterType.create(name: printer_model)
      end
    end

    # Assign printers to printer types
    Printer.all.each do |printer|
      printer_type = PrinterType.where(name: printer.model).first

      printer.update(printer_type_id: printer_type.id)
    end

    # Remove printer model column
    remove_column :printers, :model, :string
  end
end
