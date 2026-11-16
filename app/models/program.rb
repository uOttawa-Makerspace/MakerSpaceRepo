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

  # Adds the user to the program. The insert has no named conflict target (ON CONFLICT DO NOTHING), so once the
  # unique index on (user_id, program_type) exists it does nothing when the user already holds the program, even
  # under a race, and before the index exists it is a plain insert; it never looks the index up. Returns true when
  # this call added the row, false when the user was already in the program.
  def self.join(user, program_type)
    insert({ user_id: user.id, program_type: program_type }).rows.any?
  end

  # Volunteer programs follow the volunteer's last visit to the site: inactive when not seen for two months (or
  # never), active again once seen. Derived from last_seen_at only, so a repeat run changes nothing
  # (config/recurring.yml, nightly).
  def self.refresh_volunteer_activity!(now = Time.current)
    cutoff = now - 2.months
    volunteers = where(program_type: VOLUNTEER, user_id: User.select(:id))
    seen = User.where("users.last_seen_at >= ?", cutoff).select(:id)

    # Two set-based statements. Only rows whose value changes are written (and get a new updated_at).
    volunteers.where(active: [true, nil]).where.not(user_id: seen).update_all(active: false, updated_at: now)
    volunteers.where(active: [false, nil]).where(user_id: seen).update_all(active: true, updated_at: now)
  end
end
