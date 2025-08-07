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
  # Assigns the new lists of skills.
  # los_en: string format of english skills
  # los_fr: string format of french skills
  def create_list_of_skills(los_en, los_fr)
    self.list_of_skills_en = los_en
    self.list_of_skills_fr = los_fr
  end

  ##
  # returns and array containing every skill ever listed
  def all_skills
    arr = []
  
    Training.all.each do |t|
      next if t.list_of_skills_en.nil?
      t.tokenize_info_en.each do |sk|
          arr << sk
      end
    end
    arr
  end

  def filter_by_attributes(value)
    if value
      if value == "search="
        all_skills
      else
        value = value.split("=").last.gsub("+", " ")
        where(
          tokenize_info_en.each do |sk|
          "LOWER(#{sk}) like LOWER(?)"
          "%#{value}%"
          end 
        )
      end
      
    else
      all_skills
    end
  end
end
