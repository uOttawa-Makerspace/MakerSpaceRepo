# frozen_string_literal: true

class ChangeBadgeIdFromProficientProject < ActiveRecord::Migration[5.0]
  def change
    transfer_info_from_badge_id_to_badge_template
    remove_column :proficient_projects, :badge_id
  end

  def transfer_info_from_badge_id_to_badge_template
    ProficientProject.all.each do |pp|
      badge_template = BadgeTemplate.find_by(acclaim_template_id: pp.badge_id)
      pp.badge_template = badge_template
      pp.save
    end
  end
end
