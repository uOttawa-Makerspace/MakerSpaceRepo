class ProjectKit < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :proficient_project, optional: true
  validates :user, presence: true
  validates :proficient_project, presence: true
end
