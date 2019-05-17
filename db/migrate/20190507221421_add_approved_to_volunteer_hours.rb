class AddApprovedToVolunteerHours < ActiveRecord::Migration
  def change
    add_column :volunteer_hours, :approval, :boolean
  end
end
