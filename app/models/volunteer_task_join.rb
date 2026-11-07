# frozen_string_literal: true

class VolunteerTaskJoin < ApplicationRecord
  belongs_to :volunteer_task, optional: true
  belongs_to :user, optional: true

  # joined: on the task now. The other three are the endings: the task's request was approved (completed),
  # the volunteer removed themselves (left) or staff removed them (removed). Not named active: the active
  # column already gives active?.
  enum :state, { joined: "joined", completed: "completed", left: "left", removed: "removed" }, validate: true

  # validates_uniqueness_of :user_id, scope: :volunteer_task_id

  scope :active, -> { where(active: true) }
  scope :not_active, -> { where(active: false) }
  scope :user_type_volunteer, -> { where(user_type: "Volunteer") }
end
