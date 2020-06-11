# frozen_string_literal: true

class AddBadgeIdToBadges < ActiveRecord::Migration[5.0]
  def change
    add_column :badges, :badge_id, :string
  end
end
