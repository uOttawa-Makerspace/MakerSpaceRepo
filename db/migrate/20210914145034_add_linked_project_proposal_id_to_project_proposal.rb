class AddLinkedProjectProposalIdToProjectProposal < ActiveRecord::Migration[6.0]
  def change
    add_reference :project_proposals, :linked_project_proposal, index: true
  end
end
