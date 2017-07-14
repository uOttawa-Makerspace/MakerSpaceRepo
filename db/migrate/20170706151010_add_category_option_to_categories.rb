class AddCategoryOptionToCategories < ActiveRecord::Migration
  def up
    add_reference :categories, :category_option, index: true, foreign_key: true
  end
end
