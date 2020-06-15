# frozen_string_literal: true

class AddReputationToUser < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :reputation, :integer, default: 0
  end
end
