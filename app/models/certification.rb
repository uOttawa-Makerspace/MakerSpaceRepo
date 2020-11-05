# frozen_string_literal: true

class Certification < ApplicationRecord
  belongs_to :user
  belongs_to :training_session
  has_one :space, through: :training_session
  has_one :training, through: :training_session

  validates :user, presence: { message: 'A user is required.' }
  validates :training_session, presence: { message: 'A training session is required.' }
  validate :unique_cert

  scope :between_dates_picked, ->(start_date, end_date) { where('created_at BETWEEN ? AND ? ', start_date, end_date) }

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

  def self.get_highest_level_from_training(training_id, user_id)
    training_session = TrainingSession.includes(:users).where(training_id: training_id, training_sessions_users: { user_id: user_id })
    certification = Proc.new{ |user_id, training_session_id| Certification.find_by(user_id: user_id, training_session_id: training_session_id) }
    if training_session.find_by(level: 'Advanced').present? && certification.call(user_id, training_session.find_by(level: 'Advanced').id).present?
      training_session.find_by(level: 'Advanced').id
    elsif training_session.find_by(level: 'Intermediate').present? && certification.call(user_id, training_session.find_by(level: 'Intermediate').id).present?
      training_session.find_by(level: 'Intermediate').id
    elsif training_session.find_by(level: 'Beginner').present? && certification.call(user_id, training_session.find_by(level: 'Beginner').id).present?
      training_session.find_by(level: 'Beginner').id
    end
  end

  def self.highest_certifications(user_id)
    training_ids = []
    ts_ids = []
    all.find_each do |cert|
      training_ids << cert.training_session.training_id
    end
    training_ids.uniq!
    training_ids.each do |tr|
      ts_ids << get_highest_level_from_training(tr, user_id)
    end
    where(training_session_id: ts_ids)
  end

end
