class CreateJobOrderQuoteTypeExtras < ActiveRecord::Migration[6.1]
  def change
    create_table :job_order_quote_type_extras do |t|
      t.references :job_type_extra, index: true, foreign_key: true
      t.references :job_order_quote, index: true, foreign_key: true
      t.decimal :price, precision: 10, scale: 2
      t.timestamps
    end
  end
end
