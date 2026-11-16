# One row per admin resend of the claim email of an unclaimed CC Money row: who resent it, when, to which address. Rows
# are only ever added. Additive: no existing table or row is touched; down drops the new table only.
class CreateCcMoneyClaimEmailResends < ActiveRecord::Migration[8.1]
  def change
    create_table :cc_money_claim_email_resends do |t|
      t.integer :cc_money_id, null: false
      t.integer :admin_id, null: false
      t.string :email, null: false
      t.datetime :created_at, null: false
    end
    add_index :cc_money_claim_email_resends, :cc_money_id
    add_index :cc_money_claim_email_resends, :admin_id
    add_foreign_key :cc_money_claim_email_resends, :cc_moneys, on_delete: :restrict
    add_foreign_key :cc_money_claim_email_resends, :users, column: :admin_id, on_delete: :restrict
  end
end
