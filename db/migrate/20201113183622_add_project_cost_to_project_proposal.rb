class AddProjectCostToProjectProposal < ActiveRecord::Migration[6.0]
  def change
    add_column :project_proposals, :project_cost, :integer
  end
end
