class CreatePriceRules < ActiveRecord::Migration
  def change
    create_table :price_rules do |t|
      t.string :shopify_price_rule_id
      t.string :title
      t.integer :value
      t.integer :cc
      t.integer :usage_limit

      t.timestamps null: false
    end
  end
end
