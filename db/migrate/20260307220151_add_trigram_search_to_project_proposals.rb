class AddTrigramSearchToProjectProposals < ActiveRecord::Migration[7.2]
  def up
    add_index :project_proposals, :title, using: :gin, opclass: :gin_trgm_ops
  end

  def down
    remove_index :project_proposals, :title
  end
end
