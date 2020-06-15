# frozen_string_literal: true

class CreateOrderStatuses < ActiveRecord::Migration[5.0]
  def change
    create_table :order_statuses do |t|
      t.string :name

      t.timestamps null: false
    end
  end
end
