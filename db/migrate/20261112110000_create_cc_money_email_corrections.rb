# One row per correction of the purchase email of an unclaimed CC Money row: who changed it, when, from which address
# to which. Rows are only ever added. Additive: no existing table or row is touched; down drops the new table only.
class CreateCcMoneyEmailCorrections < ActiveRecord::Migration[8.1]
  def change
    create_table :cc_money_email_corrections do |t|
      t.integer :cc_money_id, null: false
      t.integer :admin_id, null: false
      t.string :old_email
      t.string :new_email, null: false
      t.datetime :created_at, null: false
    end
    add_index :cc_money_email_corrections, :cc_money_id
    add_index :cc_money_email_corrections, :admin_id
    add_foreign_key :cc_money_email_corrections, :cc_moneys, on_delete: :restrict
    add_foreign_key :cc_money_email_corrections, :users, column: :admin_id, on_delete: :restrict
  end
end
