class VolunteerTaskJoin < ActiveRecord::Base
  belongs_to :volunteer_task
  belongs_to :user

  # validates_uniqueness_of :user_id, scope: :volunteer_task_id

  scope :active, -> {where(active: true)}
  scope :not_active, -> {where(active: false)}
end
