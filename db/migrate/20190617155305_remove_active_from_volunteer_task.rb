class RemoveActiveFromVolunteerTask < ActiveRecord::Migration
  def change
    remove_column :active, :volunteer_tasks
  end
end
