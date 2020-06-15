# frozen_string_literal: true

class RemoveCategoriesFromQuestions < ActiveRecord::Migration[5.0]
  def change
    remove_column :questions, :category, :string
  end
end
