class CreateJobOrderQuoteServices < ActiveRecord::Migration[6.1]
  def change
    create_table :job_order_quote_services do |t|
      t.references :job_service, foreign_key: true, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.timestamps
    end
  end
end
