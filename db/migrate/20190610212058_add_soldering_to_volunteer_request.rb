class AddSolderingToVolunteerRequest < ActiveRecord::Migration
  def change
    add_column :volunteer_requests, :soldering, :string, default: "No Experience"
  end
end
