class AddAdditionalInfoToKeys < ActiveRecord::Migration[7.0]
  def change
    add_column :keys, :additional_info, :string, default: ""
    remove_column :key_transactions, :notes, :string
  end
end
