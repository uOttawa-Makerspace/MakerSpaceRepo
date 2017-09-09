class RemovePiReaderFromLabSessions < ActiveRecord::Migration
  def change
    remove_reference :lab_sessions, :pi_reader, index: true, foreign_key: true
  end
end
