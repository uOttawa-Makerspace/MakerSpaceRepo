class RemoveCategoriesFromQuestions < ActiveRecord::Migration
  def change
    remove_column :questions, :category, :string
  end
end
