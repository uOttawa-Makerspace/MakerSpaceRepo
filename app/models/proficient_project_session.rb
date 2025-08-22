class ProficientProjectSession < ApplicationRecord
  belongs_to :proficient_project
  belongs_to :user
  belongs_to :certification, dependent: :destroy

  validates :level, inclusion: { in: %w[Beginner Intermediate Advanced], message: "A level is required"}

  scope :between_dates_picked,
        ->(start_date, end_date) {

          where(
            "training_sessions.created_at BETWEEN ? AND ?",
            start_date,
            end_date
          )

        }

  scope :filter_by_date_range,-> { un }
        ->(range) {
          case range
          when "30_days"
            where("proficient_project_sessions.created_at >= ?", 30.days.ago)
          when "90_days"
            where("proficient_project_sessions.created_at >= ?", 90.days.ago)
          when "1_year"
            where("proficient_project_sessions.created_at >= ?", 1.year.ago)
          when "2024"
            where(proficient_project_sessions: { created_at: Date.new(2024).all_year })
          when "2023"
            where(proficient_project_sessions: { created_at: Date.new(2023).all_year })
          when "2022"
            where(proficient_project_sessions: { created_at: Date.new(2022).all_year })
          when "2021"
            where(proficient_project_sessions: { created_at: Date.new(2021).all_year })
          when "2020"
            where(proficient_project_sessions: { created_at: Date.new(2020).all_year })
          else
            all
          end.tap do |scope|
            Rails.logger.debug "Generated Scope SQL: #{scope.to_sql}"
          end
        }

  def levels
    %w[Beginner Intermediate Advanced]
  end

  def completed?
    !certification_id.nil?
  end

  def self.return_levels
    %w[Beginner Intermediate Advanced]
  end
end
