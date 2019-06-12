class VolunteerTask < ActiveRecord::Base
  belongs_to :user
  has_many :volunteer_hours, dependent: :destroy
  has_many :volunteer_task_joins, dependent: :destroy
  belongs_to :space
end
