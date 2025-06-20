# frozen_string_literal: true

class Certification < ApplicationRecord
  belongs_to :user, class_name: "User", optional: true
  belongs_to :demotion_staff, class_name: "User", optional: true
  belongs_to :training_session, optional: true
  belongs_to :proficient_project_session, optional: true
  has_one :space, through: :training_session
  has_one :training, through: :training_session
  has_many :badges
  has_many :badge_templates, through: :training

  validates :user, presence: { message: "A user is required." }

  default_scope -> { where(active: true) }
  scope :between_dates_picked,
        ->(start_date, end_date) {un
          where("created_at BETWEEN ? AND ? ", start_date, end_date)
        }
  scope :inactive, -> { unscoped.where(active: false) }

  def trainer
    training_session.user.name
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
    training_ids = joins(:training).pluck(:training_id)
    trainings = Training.where(id: training_ids)
    certs = []
    trainings.each do |training|
      certs << certification_highest_level(training.id, user_id)
    end
    certs
  end

  def self.certification_highest_level(training_id, user_id)
    certifications =
      joins(:user, :training_session).where(
        training_sessions: {
          training_id: training_id
        },
        user_id: user_id
      )
    level = certifications.pluck(:level)
    if level.include?("Advanced")
      certifications.where(training_sessions: { level: "Advanced" }).last
    elsif level.include?("Intermediate")
      certifications.where(training_sessions: { level: "Intermediate" }).last
    elsif level.include?("Beginner")
      certifications.where(training_sessions: { level: "Beginner" }).last
    end
  end

  def self.filter_by_attribute(value)
    if value.present?
      inactive.joins(:user, :training).where(
        "LOWER(demotion_reason) like LOWER(:value) OR
                       LOWER(users.name) like LOWER(:value) OR
                       LOWER(trainings.name) like LOWER(:value)",
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

  def get_name_en(certification)
    if training.nil?
      prof_proj_sess = ProficientProjectSession.includes(:certifications, :proficient_projects, 
:trainings).where(id: id)
      cert = Certification.joins(proficient_project_session).find(certification.id)
      proficient_project_session.proficient_project.training.name_en
    else
      training_session.training.name_en
    end
  end

  def get_name_fr(certification)
    if training.nil?
      prof_poj_sess = ProficientProjectSession.includes(:certifications, :proficient_projects, :trainings).where(id: id)
      cert = Certification.includes(proficient_project_session).find(certification.id)
      prof_proj_sess.proficient_project.training.name_fr
    else
      training_session.training.name_fr
    end
  end

  def get_skill_id(certification)
    if training.nil?
      cert = Certification.includes(proficient_project_session).find(certification.id)
      cert.proficient_project.training.skill_id
    else
      training_session.training.skill_id
    end
  end
end
