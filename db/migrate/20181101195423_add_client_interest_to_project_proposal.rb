# frozen_string_literal: true

class AddClientInterestToProjectProposal < ActiveRecord::Migration[5.0]
  def change
    add_column :project_proposals, :client_interest, :string
    add_column :project_proposals, :client_background, :string
    add_column :project_proposals, :supervisor_background, :string
  end
end
