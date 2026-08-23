class AddSeasonAndYearToProjectProposals < ActiveRecord::Migration[8.1]
  def change
    add_column :project_proposals, :season, :integer unless column_exists?(:project_proposals, :season)
    add_column :project_proposals, :year, :integer unless column_exists?(:project_proposals, :year)

    unless index_exists?(:project_proposals, %i[year season])
      add_index :project_proposals, %i[year season]
    end
  end
end