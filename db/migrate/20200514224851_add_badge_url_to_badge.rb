# frozen_string_literal: true

class AddBadgeUrlToBadge < ActiveRecord::Migration[5.0]
  def change
    add_column :badges, :badge_url, :string
  end
end
