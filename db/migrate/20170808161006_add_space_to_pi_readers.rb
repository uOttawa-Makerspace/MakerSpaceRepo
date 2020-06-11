# frozen_string_literal: true

class AddSpaceToPiReaders < ActiveRecord::Migration[5.0]
  def change
    add_reference :pi_readers, :space, index: true, foreign_key: true
  end
end
