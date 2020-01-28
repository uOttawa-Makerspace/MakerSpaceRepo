class VolunteerHour < ActiveRecord::Base
  belongs_to :user
  belongs_to :volunteer_task
  scope :approved, -> {where(:approval => true)}
  scope :rejected, -> {where(:approval => false)}
  scope :not_processed, -> {where(:approval => nil)}
  scope :processed, -> {where(:approval => [false, true])}

  def was_processed?
    if self.approval.nil?
      return false
    else
      return true
    end
  end

  def self.create_volunteer_hour_from_approval(volunteer_task_id, volunteer_id, hours)
    self.create(volunteer_task_id: volunteer_task_id, user_id: volunteer_id, total_time: hours, approval: true)
  end
end
