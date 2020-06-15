# frozen_string_literal: true

class AddWaiverFieldToUser < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :read_and_accepted_waiver_form, :boolean, default: false
  end
end
