class AddIsVirtualToProficientProjects < ActiveRecord::Migration[7.0]
  def change
    add_column :proficient_projects, :is_virtual, :boolean, default: false
  end
end
