class LearningModuleTrack < ApplicationRecord
  belongs_to :learning_module, optional: true
  belongs_to :user, optional: true

  enum :status, { in_progress: 'In progress', completed: 'Completed' }

  validates :learning_module, uniqueness: { scope: :user }
end
