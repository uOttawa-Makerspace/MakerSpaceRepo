# frozen_string_literal: true

class RenameColumnProjectIdinTableProjectJointoProjectProposalId < ActiveRecord::Migration
  def change
    rename_column :project_joins, :project_id, :project_proposal_id
  end
end
