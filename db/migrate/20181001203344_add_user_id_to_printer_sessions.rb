class AddUserIdToPrinterSessions < ActiveRecord::Migration
  def change
    add_column :printer_sessions, :user_id, :integer
    add_column :printer_sessions, :printer_id, :integer
  end
end
