class ProjectRequirement < ActiveRecord::Base
  belongs_to :proficient_project
  belongs_to :required_project, class_name: "ProficientProject"
  validates :proficient_project_id, uniqueness: { message: "This project is already a pre-requisite", scope: :required_project_id}
end
