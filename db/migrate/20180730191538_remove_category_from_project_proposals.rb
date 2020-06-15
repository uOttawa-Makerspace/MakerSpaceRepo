# frozen_string_literal: true

class RemoveCategoryFromProjectProposals < ActiveRecord::Migration[5.0]
  def change
    remove_column :project_proposals, :category, :string
  end
end
