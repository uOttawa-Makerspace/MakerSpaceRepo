class AddSkillsToVolunteerRequest < ActiveRecord::Migration
  def change
    add_column :volunteer_requests, :space_id, :integer
    add_column :volunteer_requests, :printing, :string
    add_column :volunteer_requests, :laser_cutting, :string
    add_column :volunteer_requests, :virtual_reality, :string
    add_column :volunteer_requests, :arduino, :string
    add_column :volunteer_requests, :embroidery, :string
  end
end
