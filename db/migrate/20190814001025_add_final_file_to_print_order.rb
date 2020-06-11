# frozen_string_literal: true

class AddFinalFileToPrintOrder < ActiveRecord::Migration
  def self.up
    change_table :print_orders do |t|
      t.attachment :final_file
    end
  end

  def self.down
    remove_attachment :print_orders, :final_file
  end
end
