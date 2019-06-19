class Announcement < ActiveRecord::Base
  belongs_to :user
  scope :active, -> {where(active: true)}
  scope :volunteers, -> {where(public_goal: "volunteer")}
  scope :all_users, -> {where(public_goal: "all")}
end
