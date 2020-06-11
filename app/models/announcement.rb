class Announcement < ApplicationRecord
  belongs_to :user
  scope :active, -> {where(active: true)}
  scope :volunteers, -> {where(public_goal: "volunteer")}
  scope :all_users, -> {where(public_goal: "all")}
  scope :admins, -> {where(public_goal: "admin")}
  scope :staff, -> {where(public_goal: "staff")}
end
