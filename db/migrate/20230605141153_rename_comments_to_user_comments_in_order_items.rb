class RenameCommentsToUserCommentsInOrderItems < ActiveRecord::Migration[7.0]
  def change
    rename_column :order_items, :comments, :user_comments
  end
end
