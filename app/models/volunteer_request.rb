class VolunteerRequest < ActiveRecord::Base
  belongs_to :user
  scope :approved, -> {where(:approval => true)}
  scope :rejected, -> {where(:approval => false)}
  scope :not_processed, -> {where(:approval => nil)}
end
