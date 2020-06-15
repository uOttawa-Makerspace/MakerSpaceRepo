# frozen_string_literal: true

class AddPasswordToRepositories < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :password, :string
  end
end
