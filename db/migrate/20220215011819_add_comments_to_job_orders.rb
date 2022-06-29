class AddCommentsToJobOrders < ActiveRecord::Migration[6.1]
  def change
    add_column :job_orders, :comments, :text
  end
end
