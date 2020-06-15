# frozen_string_literal: true

class ChangeuseridTouserId < ActiveRecord::Migration[5.0]
  def change
    rename_column :print_orders, :userid, :user_id
  end
end
