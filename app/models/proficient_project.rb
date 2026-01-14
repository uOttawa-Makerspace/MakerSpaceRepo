# frozen_string_literal: true
require "uri"

class ProficientProject < ApplicationRecord
  include Filterable
  has_and_belongs_to_many :users
  belongs_to :training, optional: true
  has_many :photos, dependent: :destroy
  has_many :repo_files, dependent: :destroy
  has_many :videos, dependent: :destroy
  has_many :project_requirements, dependent: :destroy
  has_many :required_projects, through: :project_requirements
  has_many :inverse_project_requirements,
           class_name: "ProjectRequirement",
           foreign_key: "required_project_id"
  has_many :inverse_required_projects,
           through: :inverse_project_requirements,
           source: :proficient_project
  has_many :cc_moneys, dependent: :destroy
  has_many :order_items, dependent: :destroy
  has_many :training_requirements, dependent: :destroy
  has_many :project_kits, dependent: :destroy
  has_many :proficient_project_sessions, dependent: :destroy
  belongs_to :drop_off_location, optional: true

  validates :title,
            presence: {
              message: "A title is required."
            },
            uniqueness: {
              message: "Title already exists"
            }
  before_save :capitalize_title
  

  scope :filter_by_level, ->(level) { where(level: level) }

  def capitalize_title
    self.title = title.capitalize
  end

  def self.filter_by_attribute(attribute, value)
    if attribute == "level"
      filter_by_level(value)
    elsif attribute == "category"
      joins(:training).where(trainings: { name: value })
    elsif attribute == "search"
      where(
        "LOWER(title) like LOWER(?) OR
                 LOWER(level) like LOWER(?) OR
                 LOWER(description) like LOWER(?)",
        "%#{value}%",
        "%#{value}%",
        "%#{value}%"
      )
    elsif attribute == "price"
      bool = true if value.eql?("Paid")
      bool = false if value.eql?("Free")
      where(proficient: bool)
    else
      self
    end
  end

  # link a training to a project
  def create_training_requirements(training_requirements_id, training_requirements_level)
    training_requirements.create(training: Training.find(training_requirements_id), level: training_requirements_level)
  end

  def update_training_requirements(training_requirements_id, training_requirements_level)
    treqs = @proficient_project.training_requirements
    treqs.each_with_index do |treq, i|
      treq.update(training_id: training_requirements_id[i], level: training_requirements_level[i])
    end
  end
  
  def extract_urls
    URI.extract(description)
  end

  def extract_valid_urls
    extract_urls.uniq.select do |url|
      begin
        uri = URI.parse(url)
        host = uri.host
        host == "wiki.makerepo.com"
      rescue URI::InvalidURIError
        false
      end
    end
  end

  def self.training_status(training_id, user_id)
    user = User.find(user_id)
    level =
      Certification
        .joins(:user, :training_session)
        .where(training_sessions: { training_id: training_id }, user: user)
        .pluck(:level)
    if level.include?("Advanced")
        "Advanced"
      elsif level.include?("Intermediate")
        "Intermediate"
      else
        "Beginner"
      end
    
  end
end
