class VolunteerTask < ActiveRecord::Base
  belongs_to :user
  belongs_to :space
  has_many :volunteer_hours, dependent: :destroy
  has_many :volunteer_task_joins, dependent: :destroy
  has_many :require_trainings
  has_many :volunteer_task_requests
end
