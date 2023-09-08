class TeamMembership < ApplicationRecord
  belongs_to :user
  belongs_to :team

  enum :role, %i[member lead], prefix: true
end
