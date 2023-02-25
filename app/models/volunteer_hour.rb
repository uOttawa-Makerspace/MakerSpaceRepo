# frozen_string_literal: true

class VolunteerHour < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :volunteer_task, optional: true
  scope :approved, -> { where(approval: true) }
  scope :rejected, -> { where(approval: false) }
  scope :not_processed, -> { where(approval: nil) }
  scope :processed, -> { where(approval: [false, true]) }

  def was_processed?
    approval.nil? ? false : true
  end

  def self.create_volunteer_hour_from_approval(
    volunteer_task_id,
    volunteer_id,
    hours
  )
    create(
      volunteer_task_id: volunteer_task_id,
      user_id: volunteer_id,
      total_time: hours,
      approval: true
    )
  end
end
