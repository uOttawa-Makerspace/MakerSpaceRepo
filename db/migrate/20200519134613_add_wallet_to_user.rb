class AddWalletToUser < ActiveRecord::Migration
  def change
    add_column :users, :wallet, :integer, default: 0
  end
end
