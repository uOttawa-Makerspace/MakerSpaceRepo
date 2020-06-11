# frozen_string_literal: true

class AddSpaceToLabSessions < ActiveRecord::Migration
  def change
    add_reference :lab_sessions, :space, index: true, foreign_key: true
  end
end
