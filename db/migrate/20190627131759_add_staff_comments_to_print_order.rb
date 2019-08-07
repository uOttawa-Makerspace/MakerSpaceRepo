class AddStaffCommentsToPrintOrder < ActiveRecord::Migration
  def change
    add_column :print_orders, :StaffComments, :text
  end
end
