class CreateJobOrderOptions < ActiveRecord::Migration[6.1]
  def change
    create_table :job_order_options do |t|
      t.references :job_order, null: false, foreign_key: true
      t.references :job_option, null: false, foreign_key: true
      t.timestamps
    end
  end
end
