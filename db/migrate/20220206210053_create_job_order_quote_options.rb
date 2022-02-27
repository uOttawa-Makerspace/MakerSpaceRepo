class CreateJobOrderQuoteOptions < ActiveRecord::Migration[6.1]
  def change
    create_table :job_order_quote_options do |t|
      t.references :job_option, foreign_key: true, null: false
      t.integer :amount, null: false
      t.timestamps
      t.references :job_order_quote, foreign_key: true, index: true
    end
  end
end
