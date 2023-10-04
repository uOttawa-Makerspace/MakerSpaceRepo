class AddPrototypeBudgetToProjectProposals < ActiveRecord::Migration[7.0]
  def change
    add_column :project_proposals, :prototype_cost, :integer
  end
end
