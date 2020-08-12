class AddHasProjectKitToProficientProject < ActiveRecord::Migration[6.0]
  def change
    add_column :proficient_projects, :has_project_kit, :boolean
  end
end
