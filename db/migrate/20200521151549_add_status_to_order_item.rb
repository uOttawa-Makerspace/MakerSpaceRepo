# frozen_string_literal: true

class AddStatusToOrderItem < ActiveRecord::Migration
  def change
    add_column :order_items, :status, :string, default: 'In progress'
  end
end
