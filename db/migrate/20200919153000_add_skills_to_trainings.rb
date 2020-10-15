class AddSkillsToTrainings < ActiveRecord::Migration[6.0]
  def change
    add_reference :trainings, :skill, index: true, foreign_key: true
  end
end
