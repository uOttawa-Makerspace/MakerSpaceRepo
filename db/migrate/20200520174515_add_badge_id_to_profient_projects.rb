# frozen_string_literal: true

class AddBadgeIdToProfientProjects < ActiveRecord::Migration[5.0]
  def change
    add_column :proficient_projects, :badge_id, :string
  end
end
