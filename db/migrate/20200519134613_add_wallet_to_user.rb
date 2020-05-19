class AddWalletToUser < ActiveRecord::Migration
  def change
    add_column :users, :wallet, :integer
  end
end
