class ProficientProjectSession < ApplicationRecord
  belongs_to :proficient_project
  belongs_to :user
  belongs_to :certification

  # A session always holds the certification it awarded and is the only record of how it was earned,
  # so a session is never deleted.
  before_destroy :refuse_destroy

  enum :level, {
         beginner: "Beginner",
         intermediate: "Intermediate",
         advanced: "Advanced",
       }, validate: true

  scope :between_dates_picked,
        ->(start_date, end_date) {

          where(
            "training_sessions.created_at BETWEEN ? AND ?",
            start_date,
            end_date
          )

        }

  def levels
    %w[Beginner Intermediate Advanced]
  end

  def completed?
    certification.present?
  end

  private

  def refuse_destroy
    errors.add(:base, :holds_certification)
    throw :abort
  end
end
