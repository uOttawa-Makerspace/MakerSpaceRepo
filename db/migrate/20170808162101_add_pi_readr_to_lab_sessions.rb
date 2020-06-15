# frozen_string_literal: true

class AddPiReadrToLabSessions < ActiveRecord::Migration[5.0]
  def change
    add_reference :lab_sessions, :pi_reader, index: true, foreign_key: true
  end
end
