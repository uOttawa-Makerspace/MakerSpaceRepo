# frozen_string_literal: true

class CreateOrders < ActiveRecord::Migration[5.0]
  def change
    create_table :orders do |t|
      t.references :order_status, foreign_key: true
      t.decimal :subtotal, precision: 12, scale: 3
      t.decimal :total,    precision: 12, scale: 3

      t.timestamps null: false
    end
  end
end
