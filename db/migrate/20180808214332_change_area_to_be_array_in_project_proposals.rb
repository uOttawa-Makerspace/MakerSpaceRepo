# frozen_string_literal: true

class ChangeAreaToBeArrayInProjectProposals < ActiveRecord::Migration
  def change
    change_column :project_proposals, :area, "varchar[] USING (string_to_array(area, ','))"
  end
end
