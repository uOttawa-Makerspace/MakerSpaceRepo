# frozen_string_literal: true

class AddImageUrlToBadgeTemplate < ActiveRecord::Migration[5.0]
  def change
    add_column :badge_templates, :image_url, :string
  end
end
