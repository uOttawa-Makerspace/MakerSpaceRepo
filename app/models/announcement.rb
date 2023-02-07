# frozen_string_literal: true

class Announcement < ApplicationRecord
  has_many :announcement_dismisses, dependent: :destroy
  belongs_to :user
  scope :active,
        -> {
          where(active: true).where(
            "(end_date >= ?) OR (end_date IS ?)",
            Date.today,
            nil
          )
        }
  scope :volunteers, -> { where(public_goal: "volunteer") }
  scope :all_users, -> { where(public_goal: "all") }
  scope :admins, -> { where(public_goal: "admin") }
  scope :staff, -> { where(public_goal: "staff") }
  scope :regular_user, -> { where(public_goal: "regular_user") }
end
