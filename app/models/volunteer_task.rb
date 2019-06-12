class VolunteerTask < ActiveRecord::Base
  belongs_to :user
  has_many :volunteer_hours
  has_many :volunteer_task_joins
end
