class AddJobOrderIdToJobServices < ActiveRecord::Migration[6.1]
  def change
    add_reference :job_services, :job_order, index: true, foreign_key: true
  end
end
