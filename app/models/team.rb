class Team < ApplicationRecord
  has_many :team_memberships, dependent: :destroy
  has_many :members, through: :team_memberships, source: :user

  validates :name, presence: { message: "A team name is required." }

  def captain
    captains = team_memberships.where(role: :captain)

    captains.empty? ? nil : team_memberships.where(role: :captain).first.user
  end
end
