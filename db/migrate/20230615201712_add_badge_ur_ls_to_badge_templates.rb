class AddBadgeUrLsToBadgeTemplates < ActiveRecord::Migration[7.0]
  def change
    add_column :badge_templates, :badge_url, :string
  end
end
