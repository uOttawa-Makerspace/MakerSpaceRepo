class CopyBadgeTemplateDescriptionToDescriptionInTraining < ActiveRecord::Migration[7.2]
  def up
    BadgeTemplate.all.each do |t|
      Training.find_by(id: t.training_id).update(description: t.badge_description) unless t.training_id.nil?
    end
  end
end
