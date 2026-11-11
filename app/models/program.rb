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
  UNIQUE_INDEX = "index_programs_on_user_id_and_program_type"

  # Adds the user to the program. The unique index decides a race: the insert does nothing when the user already
  # holds the program. Returns true when this call added it, false when the user was already in it.
  def self.join(user, program_type)
    insert({ user_id: user.id, program_type: program_type }, unique_by: UNIQUE_INDEX).rows.any?
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
