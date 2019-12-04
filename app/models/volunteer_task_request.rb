class VolunteerTaskRequest < ActiveRecord::Base
  belongs_to :volunteer_task
  belongs_to :user

  scope :approved, -> {where(:approval => true)}
  scope :rejected, -> {where(:approval => false)}
  scope :not_processed, -> {where(:approval => nil)}
  scope :processed, -> {where(:approval => [false, true])}

  def status
    if self.approval == true
      status = "Approved"
    elsif self.approval == false
      status = "Not Approved"
    else
      status = "Not accessed"
    end
    return status
  end

  def volunteer_task_join(user_id)
    self.volunteer_task.volunteer_task_joins.where(user_id: user_id, active: true).last
  end
end
