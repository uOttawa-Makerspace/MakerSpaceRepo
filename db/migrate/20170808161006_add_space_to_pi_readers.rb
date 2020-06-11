# frozen_string_literal: true

class AddSpaceToPiReaders < ActiveRecord::Migration
  def change
    add_reference :pi_readers, :space, index: true, foreign_key: true
  end
end
