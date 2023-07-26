class AddAdminCommentsToOrderItems < ActiveRecord::Migration[7.0]
  def change
    add_column :order_items, :admin_comments, :text, default: ""
  end
end
