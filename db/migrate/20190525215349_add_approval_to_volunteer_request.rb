class AddApprovalToVolunteerRequest < ActiveRecord::Migration
  def change
    add_column :volunteer_requests, :approval, :boolean
  end
end
