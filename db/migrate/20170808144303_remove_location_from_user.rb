# frozen_string_literal: true

class RemoveLocationFromUser < ActiveRecord::Migration[5.0]
  def change
    remove_column :users, :location, :string
  end
end
