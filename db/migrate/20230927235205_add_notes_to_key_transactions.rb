class AddNotesToKeyTransactions < ActiveRecord::Migration[7.0]
  def change
    add_column :key_transactions, :notes, :string, default: ""
  end
end
