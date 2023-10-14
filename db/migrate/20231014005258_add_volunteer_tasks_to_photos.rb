class AddVolunteerTasksToPhotos < ActiveRecord::Migration[7.0]
  def change
    add_column :photos, :volunteer_task_id, :integer
  end
end
