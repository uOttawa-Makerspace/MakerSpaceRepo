# frozen_string_literal: true

class AddWaiverFieldToUser < ActiveRecord::Migration
  def change
    add_column :users, :read_and_accepted_waiver_form, :boolean, default: false
  end
end
