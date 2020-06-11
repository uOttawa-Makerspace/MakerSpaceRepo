# frozen_string_literal: true

class AddReferencesToCcMoney < ActiveRecord::Migration[5.0]
  def change
    add_reference :cc_moneys, :proficient_project, index: true, foreign_key: true
  end
end
