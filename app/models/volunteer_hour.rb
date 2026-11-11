# frozen_string_literal: true

class VolunteerHour < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :volunteer_task
  validates :date_of_task, presence: true

  # Hours a person logs by hand (the hours form, create and edit) are saved in the :hand_logged
  # context: more than 0 and at most MAX_HAND_LOGGED_HOURS, on a day that is not in the future.
  # Hours awarded from an approved task take the task's hours and are saved without this context.
  # Each rule is checked when its field is new or changed, so a stored row (for example an
  # approved 36 hour award) stays editable in its other fields.
  MAX_HAND_LOGGED_HOURS = 24
  validates :total_time,
            numericality: { greater_than: 0, less_than_or_equal_to: MAX_HAND_LOGGED_HOURS },
            on: :hand_logged,
            if: -> { new_record? || will_save_change_to_total_time? }
  validate :date_of_task_not_in_future,
           on: :hand_logged,
           if: -> { date_of_task.present? && (new_record? || will_save_change_to_date_of_task?) }
  # The task of a hand-logged hour must be one its owner is on or has completed (checked when the task is
  # new or changed, so a stored hour keeps its task while its other fields are edited).
  validate :volunteer_task_worked_on,
           on: :hand_logged,
           if: -> { volunteer_task.present? && (new_record? || will_save_change_to_volunteer_task_id?) }
  # A hand-logged hour that is still awaiting review may not repeat another pending hour of the same person, task,
  # day and length (a double click or a resubmitted form). Staff-reviewed hours are not compared.
  validate :not_a_pending_repeat, on: :hand_logged, if: -> { approval.nil? && total_time.present? && date_of_task.present? }
  scope :approved, -> { where(approval: true) }
  scope :rejected, -> { where(approval: false) }
  scope :not_processed, -> { where(approval: nil) }
  scope :processed, -> { where(approval: [false, true]) }

  def was_processed?
    approval.nil? ? false : true
  end

  # Sets the attributes and saves them as hand-logged hours (see the validations above).
  # False, with the same message as the validation, when a simultaneous identical submission got through the
  # check first and the unique index on pending hours refused this one.
  def save_hand_logged(attributes)
    assign_attributes(attributes)
    save(context: :hand_logged)
  rescue ActiveRecord::RecordNotUnique
    errors.add(:base, :duplicate_pending)
    false
  end

  def self.create_volunteer_hour_from_approval(
    volunteer_task_id,
    volunteer_id,
    hours,
    date_of_task
  )
    create(
      volunteer_task_id: volunteer_task_id,
      user_id: volunteer_id,
      total_time: hours,
      date_of_task: date_of_task,
      approval: true
    )
  end

  private

  def not_a_pending_repeat
    repeat = VolunteerHour.not_processed.where(user_id: user_id, volunteer_task_id: volunteer_task_id,
                                               date_of_task: date_of_task, total_time: total_time.round(2))
    repeat = repeat.where.not(id: id) if persisted?
    errors.add(:base, :duplicate_pending) if repeat.exists?
  end

  def volunteer_task_worked_on
    return if VolunteerTaskJoin.worked_on.exists?(user_id: user_id, volunteer_task_id: volunteer_task_id)

    errors.add(:volunteer_task_id, :not_joined)
  end

  def date_of_task_not_in_future
    errors.add(:date_of_task, :in_the_future) if date_of_task.to_date > Date.current
  end
end
