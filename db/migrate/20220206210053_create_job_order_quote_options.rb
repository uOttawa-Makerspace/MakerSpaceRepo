class CreateJobOrderQuoteOptions < ActiveRecord::Migration[6.1]
  def change
    create_table :job_order_quote_options do |t|
      t.references :job_option, null: false, foreign_key: true
      t.integer :amount, null: false
      t.timestamps
    end
  end
end
