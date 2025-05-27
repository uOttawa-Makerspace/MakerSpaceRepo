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

  validates :name, presence: true, uniqueness: true

  def self.all_training_names
    order(name: :asc).pluck(:name)
  end
end
