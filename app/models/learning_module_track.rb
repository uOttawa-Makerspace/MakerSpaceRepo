class LearningModuleTrack < ApplicationRecord
  belongs_to :learning_module, optional: true
  belongs_to :user, optional: true

  enum :status, { in_progress: 'In progress', completed: 'Completed' }

  validates :learning_module, uniqueness: { scope: :user }

  # The user's track for the module, created when there is none. The unique index on
  # (user_id, learning_module_id) decides a race between two requests: the loser
  # reads the track the winner created instead of failing.
  def self.for_user_and_module!(user, learning_module)
    find_by(user: user, learning_module: learning_module) ||
      create_or_find_by!(user: user, learning_module: learning_module)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    find_by!(user: user, learning_module: learning_module)
  end

  before_save :check_scorm_status

  def check_scorm_status
    # Make sure this is a scorm object before reaching for json state
    self.status = :completed if scorm_completed?
  end

  # SCORM 2004 packages report cmi.completion_status; SCORM 1.2 packages report cmi.core.lesson_status,
  # where "completed" and "passed" both mean the learner is done.
  def scorm_completed?
    return false if scorm_state.blank?

    scorm_state['cmi.completion_status'] == 'completed' ||
      %w[completed passed].include?(scorm_state['cmi.core.lesson_status'])
  end
end
