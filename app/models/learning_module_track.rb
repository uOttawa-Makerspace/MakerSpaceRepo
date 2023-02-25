class LearningModuleTrack < ApplicationRecord
  belongs_to :learning_module, optional: true
  belongs_to :user, optional: true

  scope :completed, -> { where(status: "Completed") }
end
