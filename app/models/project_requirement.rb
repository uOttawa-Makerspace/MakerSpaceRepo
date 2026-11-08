# frozen_string_literal: true

class ProjectRequirement < ApplicationRecord
  belongs_to :proficient_project, optional: true
  belongs_to :required_project, class_name: "ProficientProject", optional: true
  validates :proficient_project_id,
            uniqueness: {
              scope: :required_project_id
            }
end
