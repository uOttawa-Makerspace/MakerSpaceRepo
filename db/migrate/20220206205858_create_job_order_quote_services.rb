class CreateJobOrderQuoteServices < ActiveRecord::Migration[6.1]
  def change
    create_table :job_order_quote_services do |t|
      t.references :job_service, foreign_key: true, null: false
      t.decimal :quantity, precision: 10, scale: 2, null: false
      t.decimal :per_unit, precision: 10, scale: 2, null: false
      t.references :job_order_quote, foreign_key: true, index: true
      t.timestamps
    end
  end
end
