class RemoveBadgeTemplateIdFromProficientProjects < ActiveRecord::Migration[7.2]
  change_table :proficient_projects do |p|
    p.remove :badge_template_id
  end
end
