class ReworkDevelopmentProgram < ActiveRecord::Migration[7.2]
  def change

    change_table :trainings do |t|
      t.rename :name, :name_en
      t.string :name_fr
      t.boolean :has_badge, default: true

      t.rename :description, :description_en
      t.string :description_fr

      t.string :list_of_skills_en
      t.string :list_of_skills_fr
    end

    create_table :training_requirements do |t|
      t.references :training, index: true, foreign_key: true
      t.references :proficient_project, index: true, foreign_key: true
      t.string :level
      t.timestamps
    end

    add_column :certifications, :level, :string

    change_table :proficient_projects do |t|
      t.remove :badge_template_id
    end

    create_table :proficient_project_sessions do |t|
      t.references :certification, index: true, foreign_key: true
      t.references :proficient_project, index: true, foreign_key: true
      t.references :user, index: true, foreign_key: true
      t.string :level
      t.timestamps
    end

    BadgeTemplate.all.find_each do |t|
      # transfer over template data to the trainings
      t.training&.update(
        name_en: t.badge_name.split('||').first.squish,
        name_fr: t.badge_name.split('||').last.squish,
        description_en: t.badge_description.split('||').first.squish,
        description_fr: t.badge_description.split('||').last.squish,
        list_of_skills_en: t.list_of_skills
      )
    end

    drop_table :badges
    drop_table :badge_requirements
    drop_table :badge_templates

    Certification.all.find_each do |c|
      if c.training_session.level.nil?
        c.update(level: "Beginner")
      else
        c.update(level: c.training_session.level)
      end
    end
  end
end
