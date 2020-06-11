# frozen_string_literal: true

class CreatePrintOrders < ActiveRecord::Migration
  def change
    create_table :print_orders do |t|
      t.integer :userid
      t.boolean :approved
      t.boolean :printed
      t.text :comments

      t.timestamps null: false
    end
  end
end
