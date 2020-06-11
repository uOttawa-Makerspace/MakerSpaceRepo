# frozen_string_literal: true

class AddUserApprovalToPrintOrder < ActiveRecord::Migration[5.0]
  def change
    add_column :print_orders, :UserApproval, :boolean
  end
end
