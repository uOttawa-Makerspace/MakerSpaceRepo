# frozen_string_literal: true

class Announcement < ApplicationRecord
  has_many :announcement_dismisses, dependent: :destroy
  belongs_to :user

  # The audiences an announcement can address: "all" is every visitor, signed in or not;
  # "regular_user" is every signed-in user.
  PUBLIC_GOALS = %w[volunteer regular_user staff admin all].freeze
  validates :public_goal, inclusion: { in: PUBLIC_GOALS }
  scope :active,
        -> {
          where(end_date: Time.zone.today..).or(where(end_date: nil)).where(
            active: :true
          )
        }
  scope :volunteers, -> { where(public_goal: "volunteer") }
  scope :all_users, -> { where(public_goal: "all") }
  scope :admins, -> { where(public_goal: "admin") }
  scope :staff, -> { where(public_goal: "staff") }
  scope :regular_user, -> { where(public_goal: "regular_user") }
end
