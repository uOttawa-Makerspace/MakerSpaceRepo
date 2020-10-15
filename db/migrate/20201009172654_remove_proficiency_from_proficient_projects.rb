class RemoveProficiencyFromProficientProjects < ActiveRecord::Migration[6.0]
  def change
    remove_column :proficient_projects, :proficient
  end
end
