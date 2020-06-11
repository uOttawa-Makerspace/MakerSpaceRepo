# frozen_string_literal: true

class RenameBadgeIdToAcclaimBadgeIdAndDeleteUsernameDescriptionImageUrl < ActiveRecord::Migration[5.0]
  def change
    rename_column :badges, :badge_id, :acclaim_badge_id
    remove_column :badges, :image_url
    remove_column :badges, :username
    remove_column :badges, :description
  end
end
