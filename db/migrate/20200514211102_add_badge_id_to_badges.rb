class AddBadgeIdToBadges < ActiveRecord::Migration
  def change
    add_column :badges, :badge_id, :string
  end
end
