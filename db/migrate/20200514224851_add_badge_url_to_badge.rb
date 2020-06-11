class AddBadgeUrlToBadge < ActiveRecord::Migration
  def change
    add_column :badges, :badge_url, :string
  end
end
