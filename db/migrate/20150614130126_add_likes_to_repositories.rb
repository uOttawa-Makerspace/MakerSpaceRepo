# frozen_string_literal: true

class AddLikesToRepositories < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :likes, :integer, default: 0
  end
end
