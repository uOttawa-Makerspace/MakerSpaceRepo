# frozen_string_literal: true

class VolunteerTaskRequest < ApplicationRecord
  belongs_to :volunteer_task, optional: true
  belongs_to :user, optional: true

  scope :approved, -> { where(approval: true) }
  scope :rejected, -> { where(approval: false) }
  scope :not_processed, -> { where(approval: nil) }
  scope :processed, -> { where(approval: [false, true]) }

  def status
    if approval == true
      "Approved"
    elsif approval == false
      "Not Approved"
    else
      "Not accessed"
    end
  end

  def volunteer_task_join
    volunteer_task
      &.volunteer_task_joins
      &.where(user_id: user_id, active: true)
      &.last
  end

  def self.filter_by_attribute(value)
    return all if value.blank?

    # Strip out any search param prefixes if passed as raw query string
    cleaned = value.to_s.sub(/^search_(pending|processed)=/, "").gsub("+", " ").strip
    return all if cleaned.blank?

    term = "%#{cleaned.downcase}%"
    left_outer_joins(:user, volunteer_task: :space).where(
      "LOWER(users.name) LIKE :term OR LOWER(users.username) LIKE :term OR LOWER(volunteer_tasks.title) LIKE :term OR LOWER(spaces.name) LIKE :term",
      term: term
    )
  end
end
