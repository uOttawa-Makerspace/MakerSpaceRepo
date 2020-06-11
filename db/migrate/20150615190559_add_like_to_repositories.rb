# frozen_string_literal: true

class AddLikeToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :like, :integer, default: 0
  end
end
