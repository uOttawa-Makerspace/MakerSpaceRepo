# frozen_string_literal: true

class Certification < ApplicationRecord
  belongs_to :user, class_name: "User"
  belongs_to :demotion_staff, class_name: "User"
  belongs_to :training_session
  has_one :space, through: :training_session
  has_one :training, through: :training_session
  has_many :badges

  validates :user, presence: { message: "A user is required." }
  validates :training_session,
            presence: {
              message: "A training session is required."
            }
  validate :unique_cert, on: :create

  default_scope -> { where(active: true) }
  scope :between_dates_picked,
        ->(start_date, end_date) {
          where("created_at BETWEEN ? AND ? ", start_date, end_date)
        }
  scope :inactive, -> { unscoped.where(active: false) }

  def trainer
    training_session.user.name
  end

  def self.to_csv(attributes)
    CSV.generate { |csv| attributes.each { |row| csv << row } }
  end

  def unique_cert
    @user_certs = user.certifications if user
    if @user_certs
      @user_certs.each do |cert|
        if (cert.training.id == training.id) &&
             (cert.training_session.level == training_session.level)
          errors.add(:string, "Certification already exists.")
          return false
        end
      end
    else
      return false
    end
    true
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
    training_ids = self.joins(:training).pluck(:training_id)
    trainings = Training.where(id: training_ids)
    certs = []
    trainings.each do |training|
      certs << self.certification_highest_level(training.id, user_id)
    end
    certs
  end

  def self.certification_highest_level(training_id, user_id)
    certifications =
      self.joins(:user, :training_session).where(
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
    self
      .all
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
end
