# frozen_string_literal: true

class AddClientTypeToProjectProposals < ActiveRecord::Migration
  def change
    add_column :project_proposals, :client_type, :string
  end
end
