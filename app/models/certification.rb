# frozen_string_literal: true

class Certification < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
  belongs_to :demotion_staff, class_name: "User", optional: true
  belongs_to :training_session, optional: true
  has_one :proficient_project_session
  has_one :space, through: :training_session
  has_one :training, through: :training_session
  has_one :proficient_project, through: :proficient_project_session
  has_many :badges
  has_many :badge_templates, through: :training

  validates :user, presence: { message: "A user is required." }
  validates :level, inclusion: { in: %w[Beginner Intermediate Advanced], message: "A level is required."}

  default_scope -> { where(active: true) }
  scope :between_dates_picked,
        ->(start_date, end_date) {unscoped.
          where("created_at BETWEEN ? AND ? ", start_date, end_date)
        }
  scope :inactive, -> { unscoped.where(active: false) }

  ##
  # manually finds the training associated with this certification. If you know an easier way of doing this using active
  # record associations, please fix this.
  def training
    if training_session.nil?
      proficient_project_session.proficient_project.training
    else
      training_session.training
    end
  end

  ##
  # manually finds the trainer associated with this certification. If you know an easier way of doing this using active
  # record associations, please fix this.
  def trainer
    if training_session.nil?
      proficient_project_session.user.name
    else
      training_session.user.name
    end
  end

  def self.to_csv(attributes)
    CSV.generate { |csv| attributes.each { |row| csv << row } }
  end

  def self.certify_user(training_session_id, user_id)
    create(user_id: user_id, training_session_id: training_session_id)
  end

  def get_badge_path
    case training_session.level
    when "Beginner"
      path = "badges/bronze.png"
    when "Intermediate"
      path = "badges/silver.png"
    when "Advanced"
      path = "badges/golden.png"
    end
    path
  end

  def self.highest_certifications(user_id)
    # training_ids = joins(:training).pluck(:training_id)
    # trainings = Training.where(id: training_ids)
    trainings = []
    user = User.find(user_id)
    user_certs = user.certifications
    user_certs.each do |cert|
      trainings << cert.training unless trainings.include? cert.training
    end
    certs = []
    trainings.each do |training|
      certs << certification_highest_level(training.id, user_id)
    end
    certs
  end

  def self.certification_highest_level(training_id, user_id)
    user = User.find(user_id)
    training_certs = []
    user.certifications.each do |cert|
      training_certs << cert if cert.training.id == training_id
    end
    
    highest_cert = training_certs.first
    training_certs.each do |cert|
      highest_cert = cert if highest_cert.level == "Beginner" && cert.level == "Intermediate"
      highest_cert = cert if cert.level == "Advanced"
    end
    highest_cert
  end

  def self.filter_by_attribute(value)
    if value.present?
      inactive.joins(:user, :training).where(
        "LOWER(demotion_reason) like LOWER(:value) OR
                       LOWER(users.name) like LOWER(:value) OR
                       LOWER(trainings.name_en) like LOWER(:value) OR
                       LOWER(trainings.name_fr) like LOWER(:value)",
        { value: "%#{value}%" }
      )
    else
      inactive
    end
  end

  def self.existent_certification(user, training, level)
    user_certs = user.certifications
    user_certs.each do |cert|
      if (cert.training.id == training.id) &&
           (cert.training_session.level == level)
        return cert
      end
    end
    false
  end

  def self.highest_level
    high_certs = []
    
      all
      .joins(:training_session)
      .group_by(&:training)
      .each do |_, certs|
        certifications = certs
        level = certifications.map { |c| c.training_session.level }
        if level.include?("Advanced")
          high_certs +=
            certifications.select { |c| c.training_session.level == "Advanced" }
        elsif level.include?("Intermediate")
          high_certs +=
            certifications.select do |c|
              c.training_session.level == "Intermediate"
            end
        elsif level.include?("Beginner")
          high_certs +=
            certifications.select { |c| c.training_session.level == "Beginner" }
        end
      end
    high_certs
  end

  def name
    I18n.locale == :fr ? name_fr : name_en
  end

  def get_name_en
    if training_session.nil?
      proficient_project_session.proficient_project.training.name_en
    else
      training_session.training.name_en
    end
  end

  def get_name_fr
    if training_session.nil?
      proficient_project_session.proficient_project.training.name_fr
    else
      training_session.training.name_fr
    end
  end

  def get_skill_id
    if training_session.nil?
      proficient_project_session.proficient_project.training.skill_id
    else
      training_session.training.skill_id
    end
  end
end
