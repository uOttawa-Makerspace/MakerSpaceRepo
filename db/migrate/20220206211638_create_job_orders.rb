class CreateJobOrders < ActiveRecord::Migration[6.1]
  def change
    create_table :job_orders do |t|
      t.references :user
      t.references :job_type
      t.references :job_order_quote
      t.text :staff_comments
      t.timestamps
    end

    create_join_table :job_orders, :job_services do |t|
      t.index :job_order_id
      t.index :job_service_id
    end
  end
end
