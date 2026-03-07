class AddSemesterToProjectProposals < ActiveRecord::Migration[7.2]
  def change
    # Track winter, fall, spring/summer
    add_column :project_proposals, :season, :integer
    add_column :project_proposals, :year, :integer

    # Index for sort and search
    add_index :project_proposals, [:year, :season]
  end
end
