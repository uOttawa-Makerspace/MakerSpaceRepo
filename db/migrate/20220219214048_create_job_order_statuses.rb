class CreateJobOrderStatuses < ActiveRecord::Migration[6.1]
  def change
    create_table :job_order_statuses do |t|
      t.references :job_order, index: true, foreign_key: true
      t.references :job_status, index: false, foreign_key: true
      t.timestamps
    end
  end
end
