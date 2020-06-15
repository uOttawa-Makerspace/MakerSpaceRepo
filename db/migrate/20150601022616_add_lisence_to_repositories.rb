# frozen_string_literal: true

class AddLisenceToRepositories < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :license, :string
  end
end
