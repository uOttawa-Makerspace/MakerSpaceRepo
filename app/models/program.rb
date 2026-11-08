# frozen_string_literal: true

class Program < ApplicationRecord
  belongs_to :user, optional: true
  validates :user,
            presence: true,
            uniqueness: {
              scope: :program_type
            }
  validates :program_type,
            presence: true
  VOLUNTEER = "Volunteer Program"
  DEV_PROGRAM = "Development Program"
  TEAMS = "Teams Program"

  # Volunteer programs follow the volunteer's last visit to the site: inactive when not seen for two months (or
  # never), active again once seen. Derived from last_seen_at only, so a repeat run changes nothing
  # (config/recurring.yml, nightly).
  def self.refresh_volunteer_activity!(now = Time.current)
    cutoff = now - 2.months
    # programs has no unique index on (user_id, program_type), only the model validation, so a user can in principle
    # hold two volunteer rows; as before, only the first one (lowest id) follows the user's last visit.
    first_rows = where(program_type: VOLUNTEER).group(:user_id).select("MIN(programs.id)")
    volunteers = where(id: first_rows, user_id: User.select(:id))
    seen = User.where("users.last_seen_at >= ?", cutoff).select(:id)

    # Two set-based statements. Only rows whose value changes are written (and get a new updated_at).
    volunteers.where(active: [true, nil]).where.not(user_id: seen).update_all(active: false, updated_at: now)
    volunteers.where(active: [false, nil]).where(user_id: seen).update_all(active: true, updated_at: now)
  end
end
