# frozen_string_literal: true

class VolunteerTaskRequest < ApplicationRecord
  belongs_to :volunteer_task
  belongs_to :user

  scope :approved, -> { where(approval: true) }
  scope :rejected, -> { where(approval: false) }
  scope :not_processed, -> { where(approval: nil) }
  scope :processed, -> { where(approval: [false, true]) }

  def status
    status = if approval == true
               'Approved'
             elsif approval == false
               'Not Approved'
             else
               'Not accessed'
             end
    status
  end

  def volunteer_task_join
    user_id = self.user_id
    volunteer_task.volunteer_task_joins.where(user_id: user_id, active: true).last
  end
end
