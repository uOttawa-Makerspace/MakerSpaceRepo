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
    I18n.locale == :fr ? name_fr : name_en
  end

  def description
    I18n.locale == :fr ? description_fr : description_en
  end

  def list_of_skills
    I18n.locale == :fr ? list_of_skills_fr : list_of_skills_en
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
    Training.all.pluck(:list_of_skills_en).flat_map { |l| l&.split(',')}.uniq
  end

  def self.all_skills_fr
    Training.all.pluck(:list_of_skills_fr).flat_map { |l| l&.split(',')}.uniq
  end

end
