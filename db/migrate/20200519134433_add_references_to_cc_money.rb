class AddReferencesToCcMoney < ActiveRecord::Migration
  def change
    add_reference :cc_moneys, :proficient_project, index: true, foreign_key: true
  end
end
