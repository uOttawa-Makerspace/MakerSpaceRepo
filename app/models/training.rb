# frozen_string_literal: true

class Training < ApplicationRecord
  include Translatable

  has_and_belongs_to_many :spaces
  has_and_belongs_to_many :questions
  # Sessions and projects hold the certifications awarded, so a training that has them cannot be deleted.
  has_many :training_sessions, dependent: :restrict_with_error
  has_many :certifications, through: :training_sessions
  has_many :require_trainings, dependent: :destroy
  has_many :proficient_projects, dependent: :restrict_with_error
  has_many :learning_modules, dependent: :destroy
  has_many :shifts, dependent: :nullify
  has_many :events, dependent: :nullify
  belongs_to :skill, optional: true

  # Column was renamed to name_en and it broke a lot
  alias_attribute :name, :name_en
  alias_attribute :description, :description_en

  # `name` stays the English column; localized_name is the current-language reader. `description`
  # reads in the current language (the alias above remains for writing).
  translates :name, prefix: "localized_"
  translates :description, :list_of_skills

  # Skill lists are stored as stripped names joined by ", " with no blank items.
  SKILL_SEPARATOR = ", "
  normalizes :list_of_skills_en, :list_of_skills_fr, with: ->(text) { Training.split_skills(text).join(SKILL_SEPARATOR) }

  validates :name_en, presence: true, uniqueness: true
  validates :name_fr, presence: true, uniqueness: true

  # The learning modules of this training the user has completed, optionally only at one level.
  # A page listing many trainings preloads learning_modules, and they are then filtered without a
  # query; otherwise one query returns the completed ones.
  def learning_modules_completed(user, level = nil)
    return completed_among_loaded_modules(user, level) if learning_modules.loaded?

    scope = learning_modules.joins(:learning_module_tracks).where(learning_module_tracks: { user: user, status: "Completed" })
    level ? scope.where(learning_modules: { level: level }) : scope
  end

  # The learning modules of this training the user has not completed yet, in their set order. Reads the loaded
  # learning_modules, so a page listing many trainings preloads them once.
  def learning_modules_remaining(user)
    completed_ids = user.completed_learning_module_ids
    learning_modules.reject { |m| completed_ids.include?(m.id) }
  end

  # The training's proficient projects that the user has been awarded. Reads the loaded
  # proficient_projects, so a page listing many trainings preloads them once.
  def awarded_proficient_projects(user)
    awarded_ids = user.awarded_proficient_project_ids
    proficient_projects.select { |project| awarded_ids.include?(project.id) }
  end

  # The proficient projects ordered by level text (projects without a level last), with the
  # Advanced ones moved to the end. Reads the loaded proficient_projects.
  def proficient_projects_by_level
    sorted = proficient_projects.sort_by.with_index { |project, index| [project.level.nil? ? 1 : 0, project.level.to_s, index] }
    sorted.rotate(sorted.count { |project| project.level == "Advanced" })
  end

  # The number of learning modules and proficient projects at the given levels.
  def recommended_hours(levels)
    wanted = [levels].flatten
    learning_modules.select { |m| wanted.include?(m.level_name) }.size +
      proficient_projects.select { |p| wanted.include?(p.level) }.size
  end

  def self.all_training_names
    order(name: :asc).pluck(:name)
  end

  # list_of_skills in the current language as an array of trimmed, non-empty skill names.
  def skill_list
    Training.split_skills(list_of_skills)
  end

  # The skill names in a stored list: stripped, with blank items dropped.
  def self.split_skills(text)
    text.to_s.split(",").map(&:strip).compact_blank
  end

  ##
  # returns and array containing every skill ever listed
  def self.all_skills_en
    pluck(:list_of_skills_en).flat_map { |l| split_skills(l) }.uniq
  end

  def self.all_skills_fr
    pluck(:list_of_skills_fr).flat_map { |l| split_skills(l) }.uniq
  end

  private

  def completed_among_loaded_modules(user, level)
    completed_ids = user.completed_learning_module_ids
    wanted = LearningModule.type_for_attribute("level").cast(level) if level
    learning_modules.select { |m| completed_ids.include?(m.id) && (level.nil? || m.level == wanted) }
  end
end
