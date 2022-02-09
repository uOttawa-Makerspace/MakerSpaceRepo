class CreateJobOrderStatuses < ActiveRecord::Migration[6.1]
  def change
    create_table :job_order_statuses do |t|
      t.references :job_status, null: false, index: true, foreign_key: true
      t.timestamps
    end
  end
end
