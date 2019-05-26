class AddUserIdToVolunteerRequest < ActiveRecord::Migration
  def change
    add_column :volunteer_requests, :user_id, :integer
  end
end
