# frozen_string_literal: true

class Training < ApplicationRecord
  include Translatable

  has_and_belongs_to_many :spaces
  has_and_belongs_to_many :questions
  has_many :training_sessions, dependent: :destroy
  has_many :certifications, through: :training_sessions
  has_many :require_trainings, dependent: :destroy
  has_many :proficient_projects, dependent: :destroy
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

  validates :name_en, presence: true, uniqueness: true
  validates :name_fr, presence: true, uniqueness: true

  # Returns all completed learning modules, optionally filters by level
  def learning_modules_completed(user, level = nil)
    scope =
      learning_modules.joins(:learning_module_tracks).where(
        learning_module_tracks: {
          user: user,
          status: 'Completed'
        }
      )

    scope = scope.where(learning_modules: { level: level }) if level
    scope
  end

  def self.all_training_names
    order(name: :asc).pluck(:name)
  end

  # list_of_skills in the current language as an array of trimmed, non-empty skill names.
  def skill_list
    list_of_skills.to_s.split(",").map(&:strip).compact_blank
  end

  ##
  # Convertes column list_of_skills_en into an array of strings
  def tokenize_info_en
    if list_of_skills_en.nil?
      arr = []
    else
      arr = list_of_skills_en.split(',')
      arr.collect(&:strip)
      arr
    end
  end
  ##
  # Converts column list_of_skills_fr into an array of strings
  def tokenize_info_fr
    if list_of_skills_fr.nil?
      arr = []
    else
      arr = list_of_skills_fr.split(',')
      arr.collect(&:strip)
      arr
    end
  end

  ##
  # returns and array containing every skill ever listed
  def self.all_skills_en
    Training.all.pluck(:list_of_skills_en).flat_map { |l| l&.split(',') }.uniq
  end

  def self.all_skills_fr
    Training.all.pluck(:list_of_skills_fr).flat_map { |l| l&.split(',') }.uniq
  end
end
