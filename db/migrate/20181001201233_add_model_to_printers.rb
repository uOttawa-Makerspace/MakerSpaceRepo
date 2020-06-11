# frozen_string_literal: true

class AddModelToPrinters < ActiveRecord::Migration[5.0]
  def change
    add_column :printers, :model, :string
    add_column :printers, :number, :string
  end
end
