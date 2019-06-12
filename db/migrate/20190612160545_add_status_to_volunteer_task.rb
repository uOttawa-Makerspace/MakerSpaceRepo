class AddStatusToVolunteerTask < ActiveRecord::Migration
  def change
    add_column :volunteer_tasks, :status, :string
  end
end
