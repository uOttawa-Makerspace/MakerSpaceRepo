class ReworkDevelopmentProgram < ActiveRecord::Migration[7.2]
  def change
    rename_column :badge_templates, :badge_name, :name
    add_column :badge_templates, :name_fr, :string
    rename_column :badge_templates, :name, :name_en
    add_column :trainings, :list_of_skills, :string
    add_column :trainings, :name_fr, :string

    BadgeTemplate.all.each do |t|
      Training.find_by(id: t.training_id).update(description: t.badge_description) unless t.training_id.nil?
    end

    BadgeTemplate.all.each do |t|
      Training.find_by(id: t.training_id).update(list_of_skills: t.list_of_skills) unless t.training_id.nil?
    end

    BadgeTemplate.all.each do |t|
      Training.find_by(id: t.training_id).update(name_fr: t.name_fr) unless t.training_id.nil?
    end

    rename_column :trainings, :name, :name_en

    add_column :trainings, :has_badge, :boolean, default: true

    drop_table :badges

    change_table :proficient_projects do |p|
      p.remove :badge_template_id
    end

    drop_table :badge_requirements

    drop_table :badge_templates

    add_column :trainings, :description_fr, :string
    change_table :trainings do |t|
      t.rename :description, :description_en
    end

    add_column :trainings, :list_of_skills_fr, :string
    change_table :trainings do |t|
      t.rename :list_of_skills, :list_of_skills_en
    end

    Training.all.each do |t|
      t.update(description_fr: t.description_en.split('||').last)
      t.update(description_en: t.description_en.split('||').first)
    end 

    Training.all.each do |t|
      t.update(name_fr: t.name_fr.split('-').last) unless t.name_fr.nil?
    end 

    create_table :training_requirements do |t|
      t.timestamps null: false
      t.references :training, index: true, foreign_key: true
      t.references :proficient_project, index: true, foreign_key: true
    end

    add_column :certifications, :level, :string
    Certification.all.each do |c|
      c.update(level: c.training_session.level) unless c.training_session.level.nil?
    end 

    create_table :proficient_project_sessions do |t|
      t.timestamps null: false
      t.references :certification, index: true, foreign_key: true
      t.references :proficient_project, index: true, foreign_key: true
      t.references :user, index: true, foreign_kay: true
      t.string :level
    end
  end
end
