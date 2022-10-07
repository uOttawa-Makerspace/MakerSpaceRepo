class AddDeletedToLabSessions < ActiveRecord::Migration[6.1]
  def change
    add_column :lab_sessions, :deleted, :boolean, default: false
  end
  def up
    LabSession.update_all(deleted: false)
  end
end
