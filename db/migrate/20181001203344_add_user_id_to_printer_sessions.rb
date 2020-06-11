# frozen_string_literal: true

class AddUserIdToPrinterSessions < ActiveRecord::Migration[5.0]
  def change
    add_column :printer_sessions, :user_id, :integer
    add_column :printer_sessions, :printer_id, :integer
  end
end
