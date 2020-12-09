class AddProjectTypeToProjectProposal < ActiveRecord::Migration[6.0]
  def change
    add_column :project_proposals, :project_type, :string
  end
end
