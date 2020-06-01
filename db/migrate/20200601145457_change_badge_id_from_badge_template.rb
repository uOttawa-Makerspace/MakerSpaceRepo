class ChangeBadgeIdFromBadgeTemplate < ActiveRecord::Migration
  def change
    rename_column :badge_templates, :badge_id, :acclaim_badge_id
  end
end
