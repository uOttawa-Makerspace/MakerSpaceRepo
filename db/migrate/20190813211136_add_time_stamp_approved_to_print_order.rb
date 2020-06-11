# frozen_string_literal: true

class AddTimeStampApprovedToPrintOrder < ActiveRecord::Migration
  def change
    add_column :print_orders, :timestamp_approved, :timestamp
  end
end
