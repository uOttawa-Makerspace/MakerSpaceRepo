# frozen_string_literal: true

class AddCategoryToProjectProposals < ActiveRecord::Migration
  def change
    add_column :project_proposals, :category, :string
  end
end
