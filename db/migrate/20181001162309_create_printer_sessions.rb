# frozen_string_literal: true

class CreatePrinterSessions < ActiveRecord::Migration[5.0]
  def change
    create_table :printer_sessions do |t|
      t.timestamps null: false
    end
  end
end
