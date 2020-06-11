# frozen_string_literal: true

class ChangeAreaDefaultInProjectProposals < ActiveRecord::Migration[5.0]
  def change
    change_column :project_proposals, :area, :string, array: true, default: []
  end
end
