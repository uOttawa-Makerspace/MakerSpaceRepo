class ProjectRequirement < ActiveRecord::Base
  belongs_to :proficient_project
  belongs_to :required_project, class_name: "ProficientProject"
end
