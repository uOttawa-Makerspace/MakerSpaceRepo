class VolunteerHour < ActiveRecord::Base
  belongs_to :user
  belongs_to :volunteer_task
end
