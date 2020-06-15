# frozen_string_literal: true

class AddProficientProjectsIdToRepoFile < ActiveRecord::Migration[5.0]
  def change
    add_column :repo_files, :proficient_project_id, :integer
  end
end
