# frozen_string_literal: true

class RemovePiReaderFromLabSessions < ActiveRecord::Migration[5.0]
  def change
    remove_reference :lab_sessions, :pi_reader, index: true, foreign_key: true
  end
end
