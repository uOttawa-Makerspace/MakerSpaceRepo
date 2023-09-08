class Team < ApplicationRecord
  has_many :team_memberships, dependent: :destroy
  has_many :members, through: :team_memberships, source: :user

  validate :validate_captain
  validates :name, presence: { message: "A team name is required." }

  def captain
    team_memberships.where(role: :captain).first
  end

  private

  def validate_captain
    count = team_memberships.where(role: :captain).count

    if count > 1
      errors.add(:members, "There can't be more than one team captain")
    elsif count.zero?
      errors.add(:members, "There has to be a team captain")
    end
  end
end
