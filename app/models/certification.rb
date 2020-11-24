# frozen_string_literal: true

class Certification < ApplicationRecord
  belongs_to :user
  belongs_to :training_session
  has_one :space, through: :training_session
  has_one :training, through: :training_session
  has_many :badges

  validates :user, presence: { message: 'A user is required.' }
  validates :training_session, presence: { message: 'A training session is required.' }
  validate :unique_cert, on: :create

  default_scope -> { where(active: true) }
  scope :between_dates_picked, ->(start_date, end_date) { where('created_at BETWEEN ? AND ? ', start_date, end_date) }
  scope :inactive, -> { unscoped.where(active: false) }

  def trainer
    training_session.user.name
  end

  def self.to_csv(attributes)
    CSV.generate do |csv|
      attributes.each do |row|
        csv << row
      end
    end
  end

  def unique_cert
    @user_certs = user.certifications if user
    if @user_certs
      @user_certs.each do |cert|
        if (cert.training.id == training.id) && (cert.training_session.level == training_session.level)
          errors.add(:string, 'Certification already exists.')
          return false
        end
      end
    else
      errors.add(:string, 'Something went wrong.')
      return false
    end
    true
  end

  def self.certify_user(training_session_id, user_id)
    create(user_id: user_id, training_session_id: training_session_id)
  end

  def get_badge_path
    case training_session.level
    when 'Beginner'
      path = 'badges/bronze.png'
    when 'Intermediate'
      path = 'badges/silver.png'
    when 'Advanced'
      path = 'badges/golden.png'
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
    certifications = self.joins(:user, :training_session).where(training_sessions: { training_id: training_id }, user_id: user_id )
    level = certifications.pluck(:level)
    if level.include?('Advanced')
      certifications.where(training_sessions: { level: 'Advanced' }).last
    elsif level.include?('Intermediate')
      certifications.where(training_sessions: { level: 'Intermediate' }).last
    elsif level.include?('Beginner')
      certifications.where(training_sessions: { level: 'Beginner' }).last
    end
  end

  def self.filter_by_attribute(value)
    if value.present?
      inactive.joins(:user, :training).
                where("LOWER(demotion_reason) like LOWER(:value) OR
                       LOWER(users.name) like LOWER(:value) OR
                       LOWER(trainings.name) like LOWER(:value)", { :value => "%#{value}%" })
    else
      inactive
    end
  end

end
