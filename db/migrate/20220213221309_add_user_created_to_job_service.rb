class AddUserCreatedToJobService < ActiveRecord::Migration[6.1]
  def change
    add_column :job_services, :user_created, :boolean, default: false
  end
end
