class AddDiscountCodeToCcMoney < ActiveRecord::Migration
  def change
    add_reference :cc_moneys, :discount_code, index: true, foreign_key: true
  end
end
