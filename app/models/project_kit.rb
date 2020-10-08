class ProjectKit < ApplicationRecord
  belongs_to :user
  belongs_to :proficient_project
  belongs_to :learning_module

  validates :user, presence: true
  # validates :proficient_project_id, presence: true
end
