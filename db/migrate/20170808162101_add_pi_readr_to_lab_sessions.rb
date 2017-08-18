class AddPiReadrToLabSessions < ActiveRecord::Migration
  def change
    add_reference :lab_sessions, :pi_reader, index: true, foreign_key: true
  end
end
