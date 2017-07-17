class AddCategoryOptionIdToCategories < ActiveRecord::Migration

  def up
    Category.all.each do |cat|
      cat.category_option_id = CategoryOption.find_by(name: cat.name).id
      cat.save!
    end
  end

  def down
  end

end
