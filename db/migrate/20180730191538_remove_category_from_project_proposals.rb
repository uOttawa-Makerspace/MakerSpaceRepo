# frozen_string_literal: true

class RemoveCategoryFromProjectProposals < ActiveRecord::Migration
  def change
    remove_column :project_proposals, :category, :string
  end
end
