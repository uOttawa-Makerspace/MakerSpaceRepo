# frozen_string_literal: true

class AddPasswordToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :password, :string
  end
end
