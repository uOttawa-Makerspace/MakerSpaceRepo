class AddExpireDateToPriceRule < ActiveRecord::Migration[5.2]
  def change
    add_column :price_rules, :expired_at, :datetime
  end
end
