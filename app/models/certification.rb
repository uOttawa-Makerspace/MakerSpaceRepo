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

  def out_of_date?
    updated_at < 2.years.ago
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
end
