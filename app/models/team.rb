class Team < ApplicationRecord
  belongs_to :captain, class_name: "User", foreign_key: "captain_id"
  has_many :team_memberships, dependent: :destroy
  has_many :members, through: :team_memberships, source: :user

  validates :captain, presence: { message: "A team captain is required." }
  validates :name, presence: { message: "A team name is required." }
end
