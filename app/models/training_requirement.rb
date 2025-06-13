class TrainingRequirement < ApplicationRecord
  belongs_to :proficient_project, optional: true
  belongs_to :training, optional: true
end