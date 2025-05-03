class AddShopifyDraftOrderIdToJobOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :job_orders, :shopify_draft_order_id, :string
  end
end
