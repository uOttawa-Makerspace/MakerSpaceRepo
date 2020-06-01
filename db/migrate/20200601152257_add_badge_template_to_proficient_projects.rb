class AddBadgeTemplateToProficientProjects < ActiveRecord::Migration
  def change
    add_reference :proficient_projects, :badge_template, index: true, foreign_key: true
  end
end
