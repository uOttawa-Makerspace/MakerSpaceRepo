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

  validates :name_en, presence: true, uniqueness: { scope: :training_level,
    message: "the same training can exist once for each of the three levels" }

  def self.all_training_names
    order(name: :asc).pluck(:name)
  end

  def localized_name
    I18n.locale == :fr ? name_fr : name_en
  end
end
