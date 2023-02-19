class CreateCouponCodes < ActiveRecord::Migration[6.1]
  def change
    create_table :coupon_codes do |t|
      t.string :code
      t.integer :cc_cost
      t.integer :dollar_cost
      t.references :user, null: true, foreign_key: true
      t.timestamps
    end
  end
end
