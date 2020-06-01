class ChangeBadgeIdFromBadgeTemplate < ActiveRecord::Migration
  def change
    rename_column :badge_templates, :badge_id, :acclaim_template_id
  end
end
