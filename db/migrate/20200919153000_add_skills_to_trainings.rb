class AddSkillsToTrainings < ActiveRecord::Migration[6.0]
  def change
    add_reference :trainings, :skills, foreign_key: true
  end
end
