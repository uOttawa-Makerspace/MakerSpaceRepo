class AddClientInterestToProjectProposal < ActiveRecord::Migration
  def change
    add_column :project_proposals, :client_interest, :string
    add_column :project_proposals, :client_background, :string
    add_column :project_proposals, :supervisor_background, :string
  end
end
