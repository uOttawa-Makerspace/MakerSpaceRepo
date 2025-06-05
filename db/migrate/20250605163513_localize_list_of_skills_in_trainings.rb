class LocalizeListOfSkillsInTrainings < ActiveRecord::Migration[7.2]
  def up
    add_column :trainings, :list_of_skills_fr, :string
    change_table :trainings do |t|
      t.rename :list_of_skills, :list_of_skills_en
    end
  end

  def down
    remove_column :trainings, :list_of_skills_fr, :string
    change_table :trainings do |t|
      t.rename :list_of_skills_en, :list_of_skills
    end
  end
end
