# frozen_string_literal: true

class AddLikeToRepositories < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :like, :integer, default: 0
  end
end
