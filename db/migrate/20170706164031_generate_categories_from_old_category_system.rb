class GenerateCategoriesFromOldCategorySystem < ActiveRecord::Migration
  def change
    Repository.all.each do |repo|
      if new_cat_name = OLD_CATEGORY_TO_CATEGORY_MODEL[repo.category]
        new_cat = Category.new(repository_id: repo.id, category_option_id: CategoryOption.find_by(name: new_cat_name).id)
        new_cat.save
        repo.category = nil
        repo.save
      end
    end
  end

  OLD_CATEGORY_TO_CATEGORY_MODEL = {
   'Internet of Things' => 'Internet of Things',
   'Virtual Reality' => 'Virtual Reality',
   'Bio-Medical' => 'Health Sciences',
   'Mobile' => 'Mobile Development',
   '3D-Model' => 'Other Projects',
   'Wearables' => 'Wearable',
  }
end
