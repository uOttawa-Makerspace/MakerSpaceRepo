class CreateJobOrderQuotes < ActiveRecord::Migration[6.1]
  def change
    create_table :job_order_quotes do |t|
      t.decimal :service_fee, precision: 10, scale: 2, null: false
      t.timestamps
    end
  end
end
