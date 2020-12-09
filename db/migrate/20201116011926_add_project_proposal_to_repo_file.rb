class AddProjectProposalToRepoFile < ActiveRecord::Migration[6.0]
  def change
    add_column :repo_files, :project_proposal_id, :integer
  end
end
