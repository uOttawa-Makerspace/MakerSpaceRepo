class AddUserCommentsToJobOrders < ActiveRecord::Migration[6.1]
  def change
    add_column :job_orders, :user_comments, :text
  end
end
