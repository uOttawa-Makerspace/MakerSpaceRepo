# frozen_string_literal: true

class VolunteerTaskJoin < ApplicationRecord
  belongs_to :volunteer_task, optional: true
  belongs_to :user, optional: true
  belongs_to :state_changed_by, class_name: "User", optional: true

  class NotJoined < StandardError; end

  JOINED_INDEX = "index_volunteer_task_joins_on_task_and_user_when_joined"

  ENDINGS = %w[completed left removed].freeze

  # joined: on the task now. The other three are the endings: the task's request was approved (completed),
  # the volunteer removed themselves (left) or staff removed them (removed). Not named active: the active
  # column already gives active?.
  enum :state, { joined: "joined", completed: "completed", left: "left", removed: "removed" }, validate: true

  # A user is joined to a task at most once at a time. Ended joins (completed, left, removed) are history
  # and do not count, so a user who left can join again.
  validates :user_id, uniqueness: { scope: :volunteer_task_id, conditions: -> { joined } }, if: :joined?

  # Ends a joined row once, with who ended it and when. `active` is kept in step with the state (false once
  # the join leaves joined), in the same update.
  def finish!(ending, by:)
    raise ArgumentError, "#{ending.inspect} is not an ending" unless ENDINGS.include?(ending.to_s)

    with_lock do
      raise NotJoined, "join #{id} is #{state}, not joined" unless joined?

      update!(state: ending, state_changed_at: Time.current, state_changed_by: by, active: false)
    end
  end

  # Joins whose task the volunteer is on or has completed: the tasks hours can be logged against.
  scope :worked_on, -> { where(state: %w[joined completed]) }
  scope :active, -> { where(active: true) }
  scope :not_active, -> { where(active: false) }
  scope :user_type_volunteer, -> { where(user_type: "Volunteer") }

  private

  # A save that loses a race for the same user and task runs in its own savepoint, so an enclosing
  # transaction stays usable, and fails with the same error as the uniqueness validation.
  def create_or_update(...)
    transaction(requires_new: true) { super }
  rescue ActiveRecord::RecordNotUnique => e
    raise unless e.message.include?(JOINED_INDEX)

    errors.add(:user_id, :taken)
    false
  end
end
