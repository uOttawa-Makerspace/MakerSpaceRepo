class ProjectKit < ApplicationRecord
  belongs_to :user
  belongs_to :proficient_project
  validates :user, presence: true
  validates :proficient_project_id, presence: true
end
