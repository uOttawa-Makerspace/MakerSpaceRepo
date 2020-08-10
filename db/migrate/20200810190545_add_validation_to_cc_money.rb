class AddValidationToCcMoney < ActiveRecord::Migration[6.0]
  def change
    add_column :cc_moneys, :linked, :boolean, default: true
  end
end
