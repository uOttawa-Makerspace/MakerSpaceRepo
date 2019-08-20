class AddUserApprovalToPrintOrder < ActiveRecord::Migration
  def change
    add_column :print_orders, :UserApproval, :boolean
  end
end
