# frozen_string_literal: true

class AddCategoryToRepositories < ActiveRecord::Migration
  def change
    add_column :repositories, :category, :string
  end
end
