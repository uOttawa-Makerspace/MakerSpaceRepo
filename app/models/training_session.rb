# frozen_string_literal: true

class TrainingSession < ApplicationRecord
  belongs_to :training
  belongs_to :user
  belongs_to :space
  has_many :certifications, dependent: :destroy
  has_many :exams, dependent: :destroy
  has_and_belongs_to_many :users, uniq: true
  validates :training, presence: { message: 'A training subject is required' }
  validates :user, presence: { message: 'A trainer is required' }
  validate :is_staff
  before_save :check_course
  scope :between_dates_picked, ->(start_date, end_date) { where('created_at BETWEEN ? AND ? ', start_date, end_date) }

  def is_staff
    errors.add(:string, 'user must be staff') unless user.staff?
  end

  def completed?
    certifications.any?
  end

  def levels
    %w[Beginner Intermediate Advanced]
  end

  def self.return_levels
    %w[Beginner Intermediate Advanced]
  end

  private

  def check_course
    self.course = nil if course == 'no course'
  end
end
