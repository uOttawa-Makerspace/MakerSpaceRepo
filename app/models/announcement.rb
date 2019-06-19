class Announcement < ActiveRecord::Base
  belongs_to :user
  scope :active, -> {where(active: true)}
  scope :volunteers, -> {where(public_goal: "volunteer")}
end
