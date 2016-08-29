class AddMacAddressToRfid < ActiveRecord::Migration
  def change
    add_column :rfids, :mac_address, :string
  end
end
