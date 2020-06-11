class CreateDiscountCodes < ActiveRecord::Migration
  def change
    create_table :discount_codes do |t|
      t.references :price_rule, index: true, foreign_key: true
      t.references :user, index: true, foreign_key: true
      t.string :shopify_discount_code_id
      t.string :code
      t.integer :usage_count

      t.timestamps null: false
    end
  end
end
