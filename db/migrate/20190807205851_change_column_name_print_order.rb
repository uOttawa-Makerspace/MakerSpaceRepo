# frozen_string_literal: true

class ChangeColumnNamePrintOrder < ActiveRecord::Migration
  def change
    rename_column :print_orders, :staffid, :staff_id
    rename_column :print_orders, :UserApproval, :user_approval
    rename_column :print_orders, :StaffComments, :staff_comments
  end
end
