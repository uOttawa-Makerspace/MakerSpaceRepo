class AddJoinsToVolunteerTasks < ActiveRecord::Migration
  def change
    add_column :volunteer_tasks, :joins, :integer
  end
end
