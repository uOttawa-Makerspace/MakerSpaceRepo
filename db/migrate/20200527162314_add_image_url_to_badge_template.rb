class AddImageUrlToBadgeTemplate < ActiveRecord::Migration
  def change
    add_column :badge_templates, :image_url, :string
  end
end
