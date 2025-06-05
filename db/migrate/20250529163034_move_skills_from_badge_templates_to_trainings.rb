class MoveSkillsFromBadgeTemplatesToTrainings < ActiveRecord::Migration[7.2]
  def up
    BadgeTemplate.all.each do |t|
      Training.find_by(id: t.training_id).update(list_of_skills: t.list_of_skills) unless t.training_id.nil?
    end
  end
end
