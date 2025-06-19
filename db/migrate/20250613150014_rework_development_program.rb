class ReworkDevelopmentProgram < ActiveRecord::Migration[7.2]
  def change
    change_table :badge_templates do |t|
      # Split name into separate languages
      t.rename :badge_name, :name_en
      t.string :name_fr
    end

    change_table :trainings do |t|
      t.string :list_of_skills
      t.rename :name, :name_en
      t.string :name_fr
      t.boolean :has_badge, default: true

      t.rename :description, :description_en
      t.string :description_fr

      t.rename :list_of_skills, :list_of_skills_en
      t.string :list_of_skills_fr
    end

    create_table :training_requirements do |t|
      t.references :training, index: true, foreign_key: true
      t.references :proficient_project, index: true, foreign_key: true
      t.timestamps
    end

    add_column :certifications, :level, :string

    change_table :proficient_projects do |t|
      t.remove :badge_template_id
    end

    create_table :proficient_project_sessions do |t|
      t.references :certification, index: true, foreign_key: true
      t.references :proficient_project, index: true, foreign_key: true
      t.string :level
      t.timestamps
    end

    drop_table :badges
    drop_table :badge_requirements
    drop_table :badge_templates

    Certification.all.find_each do |c|
      unless c.training_session.level.nil?
        c.update(level: c.training_session.level)
      end
    end

    Training.all.find_each do |t|
      t.update(
        description_en: t.description_en.split("||").first,
        description_fr: t.description_en.split("||").last
      )
      t.update(name_fr: t.name_fr.split("-").last) unless t.name_fr.nil?
    end

    BadgeTemplate.all.find_each do |t|
      next if t.training_id.nil?
      Training.find_by(id: t.training_id).update(
        name_fr: t.name_fr,
        description: t.badge_description,
        list_of_skills: t.list_of_skills
      )
    end
  end
end
