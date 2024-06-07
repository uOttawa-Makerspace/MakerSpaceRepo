# frozen_string_literal: true

class TrainingSession < ApplicationRecord
  belongs_to :training, optional: true
  belongs_to :user, optional: true
  belongs_to :space, optional: true
  has_many :certifications, dependent: :destroy
  has_many :exams, dependent: :destroy
  has_and_belongs_to_many :users, uniq: true
  belongs_to :course_name, optional: true

  validates :training, presence: { message: "A training subject is required" }
  validates :user, presence: { message: "A trainer is required" }
  validates :level, presence: { message: "A level is required" }
  validate :is_staff
  before_save :check_course

  default_scope -> { order(updated_at: :desc) }

  scope :between_dates_picked, ->(start_date, end_date) {
    where("training_sessions.created_at BETWEEN ? AND ?", start_date, end_date)
  }

  scope :filter_by_date_range, ->(range) do
    Rails.logger.debug "Selected Date Range: #{range}"
    case range
    when '30_days'
      where('training_sessions.created_at >= ?', 30.days.ago)
    when '90_days'
      where('training_sessions.created_at >= ?', 90.days.ago)
    when '1_year'
      where('training_sessions.created_at >= ?', 1.year.ago)
    when '2024'
      where(training_sessions: { created_at: Date.new(2024).all_year })
    when '2023'
      where(training_sessions: { created_at: Date.new(2023).all_year })
    when '2022'
      where(training_sessions: { created_at: Date.new(2022).all_year })
    when '2021'
      where(training_sessions: { created_at: Date.new(2021).all_year })
    when '2020'
      where(training_sessions: { created_at: Date.new(2020).all_year })
    else
      all
    end.tap { |scope| Rails.logger.debug "Generated Scope SQL: #{scope.to_sql}" }
  end

  def is_staff
    errors.add(:string, "user must be staff") unless user&.staff?
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

  def self.filter_by_attribute(value)
    if value.present?
      if value == "search="
        all
      else
        value = value.split('=').last.gsub('+', ' ').gsub('%20', ' ')
        joins(:user).where(
          "LOWER(trainings.name) LIKE LOWER(?) OR
           LOWER(users.name) LIKE LOWER(?) OR
           CAST(to_char(training_sessions.created_at, 'HH:MI mon DD YYYY') AS text) LIKE LOWER(?) OR
           LOWER(training_sessions.course) LIKE LOWER(?)",
          "%#{value}%",
          "%#{value}%",
          "%#{value}%",
          "%#{value}%"
        )
      end
    else
      all
    end
  end

  private

  def check_course
    self.course = nil if course == "no course"
  end
end