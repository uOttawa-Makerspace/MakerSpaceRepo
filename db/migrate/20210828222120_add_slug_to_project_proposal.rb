class AddSlugToProjectProposal < ActiveRecord::Migration[6.0]
  def change
    add_column :project_proposals, :slug, :string
  end
end
