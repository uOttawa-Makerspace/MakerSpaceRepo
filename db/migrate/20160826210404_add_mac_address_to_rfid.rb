# frozen_string_literal: true

class AddMacAddressToRfid < ActiveRecord::Migration[5.0]
  def change
    add_column :rfids, :mac_address, :string
  end
end
