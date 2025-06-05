class AddNameFrToBadgeTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :badge_templates, :name_fr, :string
  end
end
