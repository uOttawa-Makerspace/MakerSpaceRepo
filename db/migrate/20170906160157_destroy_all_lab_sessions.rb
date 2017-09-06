class DestroyAllLabSessions < ActiveRecord::Migration
  def up
    Space.destroy_all
    LabSession.destroy_all
  end
end
