# frozen_string_literal: true

class RemoveScoreFromProjectProposal < ActiveRecord::Migration
  def change
    remove_column :project_proposals, :score, :integer
  end
end
