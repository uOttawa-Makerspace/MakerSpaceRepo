class AddLeveltoProficientProjects < ActiveRecord::Migration
  def change
    add_column :proficient_projects, :level, :string, default: "Beginner"
  end
end
