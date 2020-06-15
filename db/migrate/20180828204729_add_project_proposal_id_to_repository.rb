# frozen_string_literal: true

class AddProjectProposalIdToRepository < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :project_proposal_id, :integer
  end
end
