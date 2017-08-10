class CreateGngCategoriesForCrpRepos < ActiveRecord::Migration
  def up
    gng2101 = CategoryOption.new(name: 'GNG2101')
    gng2101.save
    gng1103 = CategoryOption.new(name: 'GNG1103')
    gng1103.save
    Category.where(name: "Course-related Projects").each do |cat|
      course = cat.repository.title.upcase.gsub(/[^0-9A-Za-z]/, '')[0..6]
      if course == 'GNG2101'
        repo_gng_cat = Category.new(repository_id: cat.repository.id, name: course, category_option_id: gng2101.id)
        repo_gng_cat.save
      elsif course == 'GNG1103'
        repo_gng_cat = Category.new(repository_id: cat.repository.id, name: course, category_option_id: gng1103.id)
        repo_gng_cat.save
      else
        repo_gng_cat = Category.new(repository_id: cat.repository.id, name: 'Other Projects', category_option_id: CategoryOption.find_by(name: 'Other Projects').id)
        repo_gng_cat.save
      end
    end
  end
end
