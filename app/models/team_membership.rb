class TeamMembership < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :team, optional: true

  enum :role, %i[member lead captain], prefix: true

  validates_uniqueness_of :user_id, scope: :team_id
  validates_uniqueness_of :role, scope: :team_id, if: :role_captain?
end
