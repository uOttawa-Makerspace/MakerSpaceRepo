# frozen_string_literal: true

class AddDiscountCodeToCcMoney < ActiveRecord::Migration[5.0]
  def change
    add_reference :cc_moneys, :discount_code, index: true, foreign_key: true
  end
end
