class AddUserToJobOrderStatuses < ActiveRecord::Migration[6.1]
  def change
    add_reference :job_order_statuses, :user, foreign_key: true, index: true
  end
end
