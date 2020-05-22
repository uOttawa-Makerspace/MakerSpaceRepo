class AddOrderToCcMoney < ActiveRecord::Migration
  def change
    add_reference :cc_moneys, :order, index: true, foreign_key: true
  end
end
