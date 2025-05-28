class RenameNameToNameEnBadgeTemplates < ActiveRecord::Migration[7.2]
  def change
    rename_column :badge_templates, :name, :name_en
  end
end
