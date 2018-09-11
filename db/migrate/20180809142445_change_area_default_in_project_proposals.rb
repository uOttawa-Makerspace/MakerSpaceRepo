class ChangeAreaDefaultInProjectProposals < ActiveRecord::Migration
  def change
    change_column :project_proposals, :area, :string, array: true, default: []
  end
end
