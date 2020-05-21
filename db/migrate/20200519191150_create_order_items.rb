class CreateOrderItems < ActiveRecord::Migration
  def change
    create_table :order_items do |t|
      t.references :proficient_project, foreign_key: true
      t.references :order, foreign_key: true
      t.decimal :unit_price,  precision: 12, scale: 3
      t.decimal :total_price, precision: 12, scale: 3
      t.integer :quantity

      t.timestamps null: false
    end
  end
end
