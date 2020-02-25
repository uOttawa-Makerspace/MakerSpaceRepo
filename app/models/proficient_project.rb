class ProficientProject < ActiveRecord::Base
  has_and_belongs_to_many :users
  belongs_to :training
  has_many :photos,       dependent: :destroy
  has_many :repo_files,   dependent: :destroy
  has_many :videos,       dependent: :destroy
  has_many :project_requirements
  has_many :required_projects, through: :project_requirements
end
