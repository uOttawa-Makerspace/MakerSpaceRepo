class VolunteerTask < ActiveRecord::Base
  belongs_to :user
  has_many :volunteer_hours
  scope :active, -> {where(:active => true)}
end
