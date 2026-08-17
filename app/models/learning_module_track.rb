class LearningModuleTrack < ApplicationRecord
  belongs_to :learning_module, optional: true
  belongs_to :user, optional: true

  enum :status, { in_progress: 'In progress', completed: 'Completed' }

  validates :learning_module, uniqueness: { scope: :user }

  before_save :check_scorm_status

  def check_scorm_status
    # Make sure this is a scorm object before reaching for json state
    if scorm_state.present? && scorm_state['cmi.completion_status'] == 'completed'
      self.status = :completed
    end
  end
end
