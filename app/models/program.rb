# frozen_string_literal: true

class Program < ApplicationRecord
  belongs_to :user, optional: true
  validates :user,
            presence: {
              message: "A user is required."
            },
            uniqueness: {
              scope: :program_type,
              message: "An user can only join a program once"
            }
  validates :program_type,
            presence: {
              message:
                "The type of the program is required. Either 'Volunteer Program', 'Development Program', or 'Teams Program'"
            }
  VOLUNTEER = "Volunteer Program"
  DEV_PROGRAM = "Development Program"
  TEAMS = "Teams Program"

  # Volunteer programs follow the volunteer's last visit to the site: inactive when not seen for two months (or
  # never), active again once seen. Derived from last_seen_at only, so a repeat run changes nothing
  # (config/recurring.yml, nightly).
  def self.refresh_volunteer_activity!(now = Time.current)
    cutoff = now - 2.months
    User.volunteers.find_each do |user|
      program = user.programs.find_by(program_type: VOLUNTEER)
      next if program.nil?

      seen_recently = user.last_seen_at.present? && user.last_seen_at >= cutoff
      program.update(active: seen_recently) if program.active != seen_recently
    end
  end
end
