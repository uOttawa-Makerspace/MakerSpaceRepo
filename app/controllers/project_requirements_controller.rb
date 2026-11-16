# frozen_string_literal: true

class ProjectRequirementsController < ProficientProjectsController
  before_action :only_admin_access
  before_action :set_proficient_project, except: :destroy
  def create
    project_requirement =
      @proficient_project.project_requirements.build(
        required_project_id: params[:required_project_id]
      )

    write_flash(project_requirement, "errors.training.project_requirement_not_added", "Required project added.") { project_requirement.save }
    redirect_to proficient_project_path(@proficient_project.id)
  end

  def destroy
    project_requirement = ProjectRequirement.find(params[:id])
    proficient_project = project_requirement.proficient_project
    project_requirement.destroy
    flash[:notice] = "Removed Project Requirement"
    redirect_to proficient_project_path(proficient_project.id)
  end
end
