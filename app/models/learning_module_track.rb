class LearningModuleTrack < ApplicationRecord
  belongs_to :learning_module

  scope :completed, -> { where(status: 'Completed') }
end
