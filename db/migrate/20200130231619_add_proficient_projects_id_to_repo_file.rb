class AddProficientProjectsIdToRepoFile < ActiveRecord::Migration
  def change
    add_column :repo_files, :proficient_project_id, :integer
  end
end
