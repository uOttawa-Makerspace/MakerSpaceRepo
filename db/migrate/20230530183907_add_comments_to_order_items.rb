class AddCommentsToOrderItems < ActiveRecord::Migration[7.0]
  def change
    add_column :order_items, :comments, :text, default: ""
  end
end
