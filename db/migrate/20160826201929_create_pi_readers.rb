# frozen_string_literal: true

class CreatePiReaders < ActiveRecord::Migration
  def change
    create_table :pi_readers do |t|
      t.string :pi_mac_address
      t.string :pi_location

      t.timestamps null: false
    end
  end
end
