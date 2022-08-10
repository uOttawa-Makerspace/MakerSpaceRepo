class AddServiceGroupToJobOrder < ActiveRecord::Migration[6.1]
  def change
    add_reference :job_orders,
                  :job_service_group,
                  foreign_key: true,
                  index: true
  end
end
