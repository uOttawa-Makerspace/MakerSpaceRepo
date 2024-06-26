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
end
