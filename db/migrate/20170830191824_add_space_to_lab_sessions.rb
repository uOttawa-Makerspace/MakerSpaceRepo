# frozen_string_literal: true

class AddSpaceToLabSessions < ActiveRecord::Migration[5.0]
  def change
    add_reference :lab_sessions, :space, index: true, foreign_key: true
  end
end
