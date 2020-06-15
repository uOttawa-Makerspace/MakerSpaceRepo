# frozen_string_literal: true

class AddExpeditedToPrintOrder < ActiveRecord::Migration[5.0]
  def change
    add_column :print_orders, :expedited, :boolean
  end
end
