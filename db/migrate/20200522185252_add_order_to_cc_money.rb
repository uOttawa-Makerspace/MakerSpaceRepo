# frozen_string_literal: true

class AddOrderToCcMoney < ActiveRecord::Migration[5.0]
  def change
    add_reference :cc_moneys, :order, index: true, foreign_key: true
  end
end
