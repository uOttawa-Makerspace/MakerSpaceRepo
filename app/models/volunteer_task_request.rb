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
      &.joined
      &.where(user_id: user_id)
      &.last
  end

  # Pays the task's CC money and hours to the requester, at most once per user and task whatever the approval
  # history or the number of requests (CC money rows are only created here). The check and the payment run under
  # the volunteer's row lock, so two requests of one user for one task approved at the same moment pay once.
  # Returns true when it paid, false when the award already existed.
  def pay_award
    user.with_lock do
      next false if CcMoney.exists?(user_id: user_id, volunteer_task_id: volunteer_task_id)

      user.update_wallet
      CcMoney.create_cc_money_from_approval(volunteer_task_id, user_id, volunteer_task.cc)
      user.update_wallet
      VolunteerHour.create_volunteer_hour_from_approval(volunteer_task_id, user_id, volunteer_task.hours, created_at)
      true
    end
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
