class AddProjectProposalToPhoto < ActiveRecord::Migration[6.0]
  def change
    add_column :photos, :project_proposal_id, :integer
  end
end
