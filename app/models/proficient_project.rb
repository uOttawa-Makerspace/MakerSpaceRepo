class ProficientProject < ActiveRecord::Base
  has_and_belongs_to_many :users
  belongs_to :training
  has_many :photos,       dependent: :destroy
  has_many :repo_files,   dependent: :destroy
  has_many :videos,       dependent: :destroy
  has_many :project_requirements
  has_many :required_projects, through: :project_requirements
  has_many :inverse_project_requirements, class_name: "ProjectRequirement", foreign_key: "required_project_id"
  has_many :inverse_required_projects, through: :inverse_project_requirements, source: :proficient_project
end
