# frozen_string_literal: true

class TrainingSession < ApplicationRecord
  belongs_to :training, optional: true
  belongs_to :user, optional: true
  belongs_to :space, optional: true
  has_many :certifications, dependent: :destroy
  has_many :exams, dependent: :destroy
  # This used to be a has_many
  #has_many :users, through: :training_sessions_users, uniq: true
  has_and_belongs_to_many :users
  belongs_to :course_name, optional: true

  validates :training, presence: { message: "A training subject is required" }
  validates :user, presence: { message: "A trainer is required" }
  validates :level, presence: { message: "A level is required" }
  validates :space, presence: true
  validate :is_staff
  before_save :check_course

  default_scope -> { order(updated_at: :desc) }

  scope :between_dates_picked,
        ->(start_date, end_date) {

          where(
            "training_sessions.created_at BETWEEN ? AND ?",
            start_date,
            end_date
          )

        }

  scope :filter_by_date_range,
        ->(range) {
          case range
          when "30_days"
            where("training_sessions.created_at >= ?", 30.days.ago)
          when "90_days"
            where("training_sessions.created_at >= ?", 90.days.ago)
          when "1_year"
            where("training_sessions.created_at >= ?", 1.year.ago)
          when "2024"
            where(training_sessions: { created_at: Date.new(2024).all_year })
          when "2023"
            where(training_sessions: { created_at: Date.new(2023).all_year })
          when "2022"
            where(training_sessions: { created_at: Date.new(2022).all_year })
          when "2021"
            where(training_sessions: { created_at: Date.new(2021).all_year })
          when "2020"
            where(training_sessions: { created_at: Date.new(2020).all_year })
          else
            all
          end.tap do |scope|
            Rails.logger.debug "Generated Scope SQL: #{scope.to_sql}"
          end
        }

  scope :by_training, ->(training_id) { where(training_id: training_id) }

  scope :by_trainers, ->(trainer_id) { where(user_id: trainer_id) }

  scope :by_course, ->(course) { where(course_name_id: course) }

  scope :by_status,
        ->(status) {
          case status
          when "completed"
            joins(:certifications).distinct
          when "not_completed"
            left_outer_joins(:certifications).where(certifications: { id: nil })
          end
        }
  def is_staff
    errors.add(:string, "user must be staff") unless user&.staff?
  end

  def completed?
    certifications.any?
  end

  CertifyResult = Struct.new(:duplicates, :failed, :self_skipped, keyword_init: true) do
    def certified? = failed.empty?
  end

  # Certifies every enrolled user at the session level. The single implementation behind
  # Staff::TrainingSessionsController#certify_trainees and the /api/v1 certifications endpoint.
  #
  # The session row is locked for the whole check-then-create loop, so two concurrent calls
  # on the same session serialize and the second sees the first's certifications (no
  # duplicates). Users who already hold this training at this level (A5 guard,
  # Certification.held_by) are skipped and counted as duplicates.
  #
  # NOT all-or-nothing, as legacy: a trainee whose certification fails validation is
  # collected in `failed` and the loop carries on; everyone else stays certified. (Only an
  # exception, e.g. a database error, rolls the whole call back, because of the lock's
  # transaction.) Who may be a trainee is otherwise unrestricted (no attendance or space check).
  #
  # The instructor (user_id, admins included) is never certified by their own session: if they
  # are among the trainees they are skipped and `self_skipped` is true. That is neither a
  # failure nor a duplicate, so `certified?` is unaffected.
  def certify_trainees!
    duplicates = 0
    failed = []
    self_skipped = false
    with_lock do
      users.each do |graduate|
        if graduate.id == user_id
          self_skipped = true
          next
        end

        if Certification.held_by(graduate.id, training_id, level).exists?
          duplicates += 1
          next
        end

        failed << graduate unless Certification.new(user_id: graduate.id, training_session_id: id, level: level).save
      end
    end
    CertifyResult.new(duplicates: duplicates, failed: failed, self_skipped: self_skipped)
  end

  def levels
    %w[Beginner Intermediate Advanced]
  end

  def self.return_levels
    %w[General Beginner Intermediate Advanced]
  end

  def self.filter_by_attribute(value)
    if value.present?
      if value == "search="
        all
      else
        value = value.split("=").last.gsub("+", " ").gsub("%20", " ")
        joins(:user).where(
          "LOWER(trainings.name_en) LIKE LOWER(?) OR
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
