class AddSpaceIdToVolunteerTask < ActiveRecord::Migration
  def change
    add_column :volunteer_tasks, :space_id, :integer
  end
end
