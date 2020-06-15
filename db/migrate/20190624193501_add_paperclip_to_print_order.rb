# frozen_string_literal: true

class AddPaperclipToPrintOrder < ActiveRecord::Migration[5.0]
  def up
    add_attachment :print_orders, :file
  end

  def down
    remove_attachment :print_orders, :file
  end
end
