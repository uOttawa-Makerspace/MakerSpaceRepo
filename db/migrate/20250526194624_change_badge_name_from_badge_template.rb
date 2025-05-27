class ChangeBadgeNameFromBadgeTemplate < ActiveRecord::Migration[7.2]
  def change
    rename_column :badge_templates, :badge_name, :name
  end
end
