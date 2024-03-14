class AddPrinterTypes < ActiveRecord::Migration[7.0]
  def up
    # Create the PrinterType table
    create_table :printer_types do |t|
      t.string :name
      t.string :short_form, default: ""

      t.timestamps
    end

    # add printer_type_id to printers table
    add_reference :printers, :printer_type, index: true, foreign_key: true

    # populate printer types
    Printer.all.each do |printer|
      printer_model = printer.model
      printer_types = PrinterType.where(name: printer_model)

      printer_type = nil
      if printer_types.empty?
        printer_type = PrinterType.create(name: printer_model)
      else
        printer_type = printer_types.first
      end

      printer.update(printer_type_id: printer_type.id)
    end

    # Remove printer model column
    remove_column :printers, :model, :string
  end

  def down
    add_column :printers, :model, :string

    Printer.all.each do |printer|
      printer_type = PrinterType.find_by(id: printer.printer_type_id)

      printer.update(model: printer_type.name) unless printer_type.nil?
    end

    remove_reference :printers, :printer_type

    drop_table :printer_types, if_exists: true
  end
end
