# frozen_string_literal: true

class RemoveLikesFromRepository < ActiveRecord::Migration
  def change
    remove_column :repositories, :likes, :integer
    add_column :repositories, :make, :integer, default: 0
  end
end
