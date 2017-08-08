class AddCategoryOptionReferenceToCategories < ActiveRecord::Migration
  def change
    add_reference :categories, :category_option, index: true, foreign_key: true
  end
end
