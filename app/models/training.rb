# frozen_string_literal: true

class Training < ApplicationRecord
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
  has_many :badge_templates

  # Column was renamed to name_en and it broke a lot
  alias_attribute :name, :name_en
  alias_attribute :description, :description_en

  validates :name_en, presence: true, uniqueness: true
  validates :name_fr, presence: true, uniqueness: true

  def self.all_training_names
    order(name: :asc).pluck(:name)
  end

  def localized_name
    # Pick one, show other if unavailable
    if I18n.locale == :fr
      name_fr || name_en
    else
      name_en || name_fr
    end
  end

  def description
    if I18n.locale == :fr
      description_fr || description_en
    else
      description_en || description_fr
    end
  end

  def list_of_skills
    if I18n.locale == :fr
      list_of_skills_fr || list_of_skills_en
    else
      list_of_skills_en || list_of_skills_fr
    end
  end
end
