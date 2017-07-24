class RemoveAdminFkFromTrainings < ActiveRecord::Migration
  def change
    remove_column :trainings, :user_id, :references
  end
end
