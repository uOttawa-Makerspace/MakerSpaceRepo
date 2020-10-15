class LearningModuleTrack < ApplicationRecord
  belongs_to :learning_module
  belongs_to :user

  scope :completed, -> { where(status: 'Completed') }
end
