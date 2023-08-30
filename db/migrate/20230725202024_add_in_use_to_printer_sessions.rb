class AddInUseToPrinterSessions < ActiveRecord::Migration[7.0]
  def change
    add_column :printer_sessions, :in_use, :boolean, default: false
  end
end
