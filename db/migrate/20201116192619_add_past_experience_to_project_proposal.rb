class AddPastExperienceToProjectProposal < ActiveRecord::Migration[6.0]
  def change
    add_column :project_proposals, :past_experiences, :string
  end
end
