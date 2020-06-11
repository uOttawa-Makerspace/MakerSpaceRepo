# frozen_string_literal: true

class ChangeStaffIdFromDoublePrecisionToInt < ActiveRecord::Migration[5.0]
  def change
    change_column :print_orders, :staffid, :integer
  end
end
