# frozen_string_literal: true

class AddCategoryToRepositories < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :category, :string
  end
end
