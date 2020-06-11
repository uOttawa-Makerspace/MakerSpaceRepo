# frozen_string_literal: true

class AddProjectProposalIdToCategories < ActiveRecord::Migration[5.0]
  def change
    add_column :categories, :project_proposal_id, :integer
  end
end
