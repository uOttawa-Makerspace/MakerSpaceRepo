class AddDraftOrderTrackingToLockerRentals < ActiveRecord::Migration[7.2]
  def change
    add_column :locker_rentals, :shopify_draft_order_id, :string
  end
end
