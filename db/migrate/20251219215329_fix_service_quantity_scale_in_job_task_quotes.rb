class FixServiceQuantityScaleInJobTaskQuotes < ActiveRecord::Migration[7.0]
  def up
    change_column :job_task_quotes, :service_quantity, :decimal, precision: 10, scale: 4
  end

  def down
    change_column :job_task_quotes, :service_quantity, :decimal, precision: 10, scale: nil
  end
end