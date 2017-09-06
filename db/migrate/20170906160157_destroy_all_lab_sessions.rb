class DestroyAllLabSessions < ActiveRecord::Migration
  def up
    PiReader.destroy_all
    LabSession.destroy_all
    Space.destroy_all
  end
end
