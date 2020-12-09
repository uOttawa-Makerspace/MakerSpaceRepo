class AddListOfSkillsToBadgeTemplate < ActiveRecord::Migration[6.0]
  def change
    add_column :badge_templates, :list_of_skills, :string
  end
end
