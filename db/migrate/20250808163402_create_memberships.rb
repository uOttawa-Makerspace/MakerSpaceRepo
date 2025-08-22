class CreateMemberships < ActiveRecord::Migration[7.2]
  def change
    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.string :membership_type
      t.datetime :start_date
      t.datetime :end_date
      t.string :shopify_draft_order_id
      t.string :status, default: "paid"

      t.timestamps
    end
  end
end
