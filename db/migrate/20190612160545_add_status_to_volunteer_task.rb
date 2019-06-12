class AddStatusToVolunteerTask < ActiveRecord::Migration
  def change
    add_column :volunteer_tasks, :status, :string, default: "open"
  end
end
