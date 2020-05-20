class AddBadgeIdToProfientProjects < ActiveRecord::Migration
  def change
    add_column :proficient_projects, :badge_id, :string
  end
end
