class ProficientProjectSession < ApplicationRecord
  belongs_to :proficient_project
  belongs_to :user
  belongs_to :certification, dependent: :destroy

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
end
