class AddListOfSkillsToTrainings < ActiveRecord::Migration[7.2]
  def change
    add_column :trainings, :list_of_skills, :string
  end
end
